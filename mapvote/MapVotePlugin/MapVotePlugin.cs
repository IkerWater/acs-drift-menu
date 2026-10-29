using System.Text.Json;
using AssettoServer.Network.Tcp;
using AssettoServer.Server;
using AssettoServer.Server.Configuration;
using AssettoServer.Server.Plugin;
using AssettoServer.Shared.Network.Packets.Shared;
using AssettoServer.Shared.Services;
using Microsoft.Extensions.Hosting;
using Serilog;

namespace MapVotePlugin;

/// <summary>
/// Votacion publica de cambio de mapa, independiente de los presets.
/// Reglas: cualquiera propone; umbral = mas del 50 % de los conectados al iniciar;
/// aprobada en cuanto se supera; 60 s de duracion; 120 s de espera tras iniciar una votacion.
/// </summary>
public class MapVotePlugin : CriticalBackgroundService, IAssettoServerAutostart
{
    private sealed class VoteState
    {
        public required TrackEntry Entry { get; init; }
        public required byte ProposerSession { get; init; }
        public required string ProposerName { get; init; }
        public required int ConnectedAtStart { get; init; }
        public required int Needed { get; init; }
        public required DateTime EndsAt { get; init; }
        public Dictionary<byte, bool> Votes { get; } = new();
        public int Yes => Votes.Count(v => v.Value);
        public int No => Votes.Count(v => !v.Value);
    }

    private readonly MapVoteConfiguration _config;
    private readonly ACServerConfiguration _acServerConfiguration;
    private readonly EntryCarManager _entryCarManager;
    private readonly TrackCatalog _catalog;
    private readonly IHostApplicationLifetime _lifetime;

    private readonly object _lock = new();
    private VoteState? _vote;
    private TrackEntry? _pendingEntry;
    private DateTime _pendingAt;
    private DateTime _nextAllowedStart = DateTime.MinValue;

    public MapVotePlugin(MapVoteConfiguration config,
        ACServerConfiguration acServerConfiguration,
        EntryCarManager entryCarManager,
        TrackCatalog catalog,
        IHostApplicationLifetime applicationLifetime) : base(applicationLifetime)
    {
        _config = config;
        _acServerConfiguration = acServerConfiguration;
        _entryCarManager = entryCarManager;
        _catalog = catalog;
        _lifetime = applicationLifetime;
    }

    // ------------------------------------------------------------------
    // Utilidades
    // ------------------------------------------------------------------

    private static void Send(ACTcpClient client, string message)
        => client.SendPacket(new ChatMessage { SessionId = 255, Message = message });

    private void Broadcast(string message)
        => _entryCarManager.BroadcastPacket(new ChatMessage { SessionId = 255, Message = message });

    // [VERIFICAR] EntryCarManager.ConnectedCars y EntryCar.Client en tu version de AssettoServer.
    private int ConnectedCount()
        => _entryCarManager.ConnectedCars.Values.Count(c => c.Client != null);

    // [VERIFICAR] ACServerConfiguration.Server.Track / TrackConfig en tu version.
    private (string Track, string Layout) CurrentTrack
        => (_acServerConfiguration.Server.Track ?? "", _acServerConfiguration.Server.TrackConfig ?? "");

    private string CurrentName()
    {
        var (track, layout) = CurrentTrack;
        return _catalog.Find(track, layout)?.Name ?? (layout.Length > 0 ? $"{track} [{layout}]" : track);
    }

    private static int Remaining(DateTime until)
        => Math.Max(0, (int)Math.Ceiling((until - DateTime.UtcNow).TotalSeconds));

    // ------------------------------------------------------------------
    // Acciones de jugador
    // ------------------------------------------------------------------

    internal void StartVote(ACTcpClient client, int id)
    {
        lock (_lock)
        {
            if (_pendingEntry != null)
            {
                Send(client, "[Mapa] Ya se esta cambiando de circuito.");
                return;
            }

            if (_vote != null)
            {
                Send(client, "[Mapa] Ya hay una votacion en curso.");
                return;
            }

            var now = DateTime.UtcNow;
            if (now < _nextAllowedStart)
            {
                Send(client, $"[Mapa] Espera {Remaining(_nextAllowedStart)} s para iniciar otra votacion.");
                return;
            }

            if (!_catalog.TryGet(id, out var entry))
            {
                Send(client, "[Mapa] Mapa no valido. Usa /maplist.");
                return;
            }

            var (curTrack, curLayout) = CurrentTrack;
            if (string.Equals(entry.Track, curTrack, StringComparison.OrdinalIgnoreCase) &&
                string.Equals(entry.Layout, curLayout, StringComparison.OrdinalIgnoreCase))
            {
                Send(client, "[Mapa] Ya estas en ese mapa.");
                return;
            }

            var connected = Math.Max(1, ConnectedCount());
            _vote = new VoteState
            {
                Entry = entry,
                ProposerSession = client.SessionId,
                ProposerName = client.Name ?? "?",
                ConnectedAtStart = connected,
                Needed = connected / 2 + 1, // estrictamente mas del 50 %
                EndsAt = now.AddSeconds(_config.VoteDurationSeconds)
            };
            // La espera cuenta desde que se INICIA la votacion.
            _nextAllowedStart = now.AddSeconds(_config.CooldownSeconds);

            Broadcast($"[Mapa] {_vote.ProposerName} propone: {entry.Name}. " +
                      $"Hacen falta {_vote.Needed} de {connected} votos a favor. " +
                      $"Vota con /mapyes o /mapno ({_config.VoteDurationSeconds} s).");

            if (_config.ProposerVotesYes)
                RegisterVote(client, true);
        }
    }

    internal void CastVote(ACTcpClient client, bool yes)
    {
        lock (_lock)
        {
            if (_vote == null)
            {
                Send(client, "[Mapa] No hay ninguna votacion en curso.");
                return;
            }

            RegisterVote(client, yes);
        }
    }

    // Debe llamarse con _lock tomado.
    private void RegisterVote(ACTcpClient client, bool yes)
    {
        var vote = _vote!;
        vote.Votes[client.SessionId] = yes;
        Send(client, yes ? "[Mapa] Voto a favor registrado." : "[Mapa] Voto en contra registrado.");

        if (vote.Yes >= vote.Needed)
            Approve();
    }

    // Debe llamarse con _lock tomado.
    private void Approve()
    {
        var vote = _vote!;
        _vote = null;
        _pendingEntry = vote.Entry;
        _pendingAt = DateTime.UtcNow.AddSeconds(_config.ChangeDelaySeconds);

        Broadcast($"[Mapa] Aprobado ({vote.Yes}/{vote.Needed}): {vote.Entry.Name}. " +
                  $"Cambiando de circuito en {_config.ChangeDelaySeconds} s.");
        Log.Information("MapVote: aprobado {Name} ({Track}/{Layout})", vote.Entry.Name, vote.Entry.Track, vote.Entry.Layout);
    }

    internal void Cancel(ACTcpClient client)
    {
        lock (_lock)
        {
            if (_vote == null && _pendingEntry == null)
            {
                Send(client, "[Mapa] No hay nada que cancelar.");
                return;
            }

            _vote = null;
            _pendingEntry = null;
            Broadcast("[Mapa] Votacion/cambio cancelado por un administrador.");
        }
    }

    internal void SendList(ACTcpClient client, int page)
    {
        const int perPage = 8;
        var entries = _catalog.Entries;
        var pages = Math.Max(1, (int)Math.Ceiling(entries.Count / (double)perPage));
        page = Math.Clamp(page, 1, pages);

        Send(client, $"[Mapa] Lista {page}/{pages} (usa /mapstart <numero>):");
        foreach (var e in entries.Skip((page - 1) * perPage).Take(perPage))
            Send(client, $" {e.Id} - {e.Name}");
    }

    internal void SendStatus(ACTcpClient client)
    {
        lock (_lock)
        {
            Send(client, $"[Mapa] Actual: {CurrentName()}");
            if (_pendingEntry != null)
                Send(client, $"[Mapa] Cambiando a {_pendingEntry.Name} en {Remaining(_pendingAt)} s.");
            else if (_vote != null)
                Send(client, $"[Mapa] Votacion: {_vote.Entry.Name} - {_vote.Yes}/{_vote.Needed} a favor, " +
                             $"{Remaining(_vote.EndsAt)} s restantes.");
            else if (DateTime.UtcNow < _nextAllowedStart)
                Send(client, $"[Mapa] Proxima votacion posible en {Remaining(_nextAllowedStart)} s.");
        }
    }

    internal void Reload(ACTcpClient client)
    {
        _catalog.Reload();
        Send(client, $"[Mapa] Lista recargada: {_catalog.Entries.Count} mapas.");
    }

    // ------------------------------------------------------------------
    // Estado para el menu (via HTTP)
    // ------------------------------------------------------------------

    internal object GetStatus()
    {
        lock (_lock)
        {
            var (track, layout) = CurrentTrack;
            var v = _vote;
            return new
            {
                current = new { track, layout, name = CurrentName() },
                active = v != null,
                proposal = v == null ? null : new { id = v.Entry.Id, name = v.Entry.Name },
                proposer = v?.ProposerName,
                yes = v?.Yes ?? 0,
                no = v?.No ?? 0,
                needed = v?.Needed ?? 0,
                connectedAtStart = v?.ConnectedAtStart ?? 0,
                secondsLeft = v == null ? 0 : Remaining(v.EndsAt),
                cooldownLeft = Remaining(_nextAllowedStart),
                changing = _pendingEntry != null,
                changeInSeconds = _pendingEntry == null ? 0 : Remaining(_pendingAt),
                voteDurationSeconds = _config.VoteDurationSeconds
            };
        }
    }

    // ------------------------------------------------------------------
    // Bucle de control: caducidad de votaciones y ejecucion del cambio
    // ------------------------------------------------------------------

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                Tick();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "MapVote: error en el bucle de control");
            }

            try
            {
                await Task.Delay(500, stoppingToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }
        }
    }

    private void Tick()
    {
        TrackEntry? toApply = null;

        lock (_lock)
        {
            var now = DateTime.UtcNow;

            if (_vote != null && now >= _vote.EndsAt)
            {
                Broadcast($"[Mapa] Votacion rechazada: {_vote.Yes}/{_vote.Needed} votos a favor. " +
                          $"Sigue {CurrentName()}.");
                _vote = null;
            }

            if (_pendingEntry != null && now >= _pendingAt)
            {
                toApply = _pendingEntry;
                _pendingEntry = null;
            }
        }

        if (toApply != null) ApplyChange(toApply);
    }

    private void ApplyChange(TrackEntry entry)
    {
        try
        {
            var payload = new
            {
                track = entry.Track,
                layout = entry.Layout,
                name = entry.Name,
                restartRequested = true,
                requestedAt = DateTime.UtcNow
            };
            File.WriteAllText(_config.SelectionFile,
                JsonSerializer.Serialize(payload, new JsonSerializerOptions { WriteIndented = true }));
            Log.Information("MapVote: seleccion guardada en {File}", Path.GetFullPath(_config.SelectionFile));

            switch (_config.RestartMode)
            {
                case MapRestartMode.Exit:
                    Log.Information("MapVote: cerrando el servidor para cambiar a {Name}", entry.Name);
                    _lifetime.StopApplication();
                    break;
                case MapRestartMode.File:
                    File.WriteAllText(_config.RestartFlagFile, DateTime.UtcNow.ToString("O"));
                    Log.Information("MapVote: fichero de reinicio creado: {File}", _config.RestartFlagFile);
                    break;
            }
        }
        catch (Exception ex)
        {
            Log.Error(ex, "MapVote: no se pudo solicitar el cambio de circuito");
            Broadcast("[Mapa] Error al solicitar el cambio de circuito. Avisa a un administrador.");
        }
    }
}
