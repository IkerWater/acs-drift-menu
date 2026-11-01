using System.Reflection;
using System.Text.RegularExpressions;
using AssettoServer;
using AssettoServer.Network.Tcp;
using AssettoServer.Server;
using AssettoServer.Server.Configuration;
using AssettoServer.Shared.Network.Packets.Outgoing;
using Microsoft.Extensions.Hosting;
using Serilog;

namespace MapVotePlugin;

/// <summary>
/// Votación pública de cambio de circuito, independiente de los presets.
/// Cualquiera propone un circuito instalado; se aprueba si vota a favor más del 50 % de los
/// conectados al empezar la votación. Al aprobarse, cambia TRACK/CONFIG_TRACK en la configuración
/// en uso y reinicia AssettoServer dentro del mismo proceso (sin lanzador externo, válido en Pterodactyl).
/// </summary>
public class MapVotePlugin : BackgroundService
{
    private sealed class VoteState
    {
        public required TrackEntry Entry { get; init; }
        public required string ProposerName { get; init; }
        public required int ConnectedAtStart { get; init; }
        public required int Needed { get; init; }
        public required DateTime EndsAt { get; init; }
        public Dictionary<byte, bool> Votes { get; } = new();
        public int Yes => Votes.Count(v => v.Value);
        public int No => Votes.Count(v => !v.Value);
    }

    private const string Tag = "[Mapa]";
    private const string KickReasonText = "CAMBIO DE CIRCUITO: vuelve a entrar en unos segundos";

    private readonly MapVoteConfiguration _config;
    private readonly ACServerConfiguration _serverConfig;
    private readonly EntryCarManager _entryCarManager;
    private readonly TrackCatalog _catalog;

    private readonly Lock _lock = new();
    private VoteState? _vote;
    private TrackEntry? _pendingEntry;
    private DateTime _pendingAt;
    private DateTime _nextAllowedStart = DateTime.MinValue;
    private bool _restarting;

    public MapVotePlugin(MapVoteConfiguration config,
        ACServerConfiguration serverConfig,
        EntryCarManager entryCarManager,
        TrackCatalog catalog,
        CSPServerScriptProvider scriptProvider,
        CSPClientMessageTypeManager clientMessageTypeManager,
        CSPFeatureManager cspFeatureManager)
    {
        _config = config;
        _serverConfig = serverConfig;
        _entryCarManager = entryCarManager;
        _catalog = catalog;

        if (serverConfig.Extra.EnableClientMessages)
        {
            // Menú del juego y reconexión automática
            var luaPath = Path.Join(Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location), "lua", "mapvote.lua");
            if (File.Exists(luaPath))
                scriptProvider.AddScript(File.ReadAllText(luaPath), "mapvote.lua");
            else
                Log.Warning("MapVote: no se encuentra {Path}; solo funcionarán los comandos de chat", luaPath);

            clientMessageTypeManager.RegisterOnlineEvent<MapVoteActionPacket>(OnAction);
            // VotingPresetPlugin también la declara y añadirla dos veces rompe el arranque:
            // si ese plugin está activado, se la dejamos a él.
            var votingPreset = serverConfig.Extra.EnablePlugins?.Any(p =>
                string.Equals(p, "VotingPresetPlugin", StringComparison.OrdinalIgnoreCase)) == true;
            if (!votingPreset)
            {
                try { cspFeatureManager.Add(new CSPFeature { Name = "FREQUENT_TRACK_CHANGES" }); }
                catch (ArgumentException) { Log.Debug("MapVote: FREQUENT_TRACK_CHANGES ya declarada por otro plugin"); }
            }
        }
        else
        {
            Log.Warning("MapVote: EnableClientMessages está desactivado en extra_cfg.yml: " +
                        "no habrá menú ni reconexión automática, solo comandos de chat");
        }
    }

    // ------------------------------------------------------------------ utilidades
    private static void Send(ACTcpClient client, string message) => client.SendChatMessage($"{Tag} {message}");
    private void Broadcast(string message) => _entryCarManager.BroadcastChat($"{Tag} {message}");

    private int ConnectedCount() => _entryCarManager.ConnectedCars.Count;

    private (string Track, string Layout) CurrentTrack
    {
        get
        {
            // El circuito puede llevar el prefijo de versión mínima de CSP: "csp/2651/../mi_circuito"
            var track = _serverConfig.Server.Track ?? "";
            var idx = track.LastIndexOf("../", StringComparison.Ordinal);
            if (idx >= 0) track = track[(idx + 3)..];
            return (track, _serverConfig.Server.TrackConfig ?? "");
        }
    }

    private string CurrentName()
    {
        var (track, layout) = CurrentTrack;
        return _catalog.Find(track, layout)?.Name ?? (layout.Length > 0 ? $"{track} [{layout}]" : track);
    }

    private static int Remaining(DateTime until) => Math.Max(0, (int)Math.Ceiling((until - DateTime.UtcNow).TotalSeconds));

    // ------------------------------------------------------------------ menú (online event)
    private void OnAction(ACTcpClient client, MapVoteActionPacket packet)
    {
        switch (packet.Action)
        {
            case 1: StartVote(client, packet.Id); break;
            case 2: CastVote(client, true); break;
            case 3: CastVote(client, false); break;
        }
    }

    // ------------------------------------------------------------------ acciones de jugador
    internal void StartVote(ACTcpClient client, int id)
    {
        lock (_lock)
        {
            if (_pendingEntry != null || _restarting) { Send(client, "Ya se está cambiando de circuito."); return; }
            if (_vote != null) { Send(client, "Ya hay una votación en curso. Vota con /mapyes o /mapno."); return; }

            var now = DateTime.UtcNow;
            if (now < _nextAllowedStart) { Send(client, $"Espera {Remaining(_nextAllowedStart)} s para proponer otro circuito."); return; }
            if (!_catalog.TryGet(id, out var entry)) { Send(client, "Número no válido. Mira la lista con /maplist."); return; }

            var (curTrack, curLayout) = CurrentTrack;
            if (string.Equals(entry.Track, curTrack, StringComparison.OrdinalIgnoreCase) &&
                string.Equals(entry.Layout, curLayout, StringComparison.OrdinalIgnoreCase))
            {
                Send(client, "Ya estáis en ese circuito.");
                return;
            }

            var connected = Math.Max(1, ConnectedCount());
            _vote = new VoteState
            {
                Entry = entry,
                ProposerName = client.Name ?? "?",
                ConnectedAtStart = connected,
                Needed = connected / 2 + 1, // estrictamente más del 50 %
                EndsAt = now.AddSeconds(_config.VoteDurationSeconds)
            };
            _nextAllowedStart = now.AddSeconds(_config.CooldownSeconds);

            Broadcast($"{_vote.ProposerName} propone: {entry.Name}. Hacen falta {_vote.Needed} de {connected} votos a favor. " +
                      $"Vota con /mapyes o /mapno ({_config.VoteDurationSeconds} s).");

            if (_config.ProposerVotesYes)
                RegisterVote(client, true);
        }
    }

    internal void CastVote(ACTcpClient client, bool yes)
    {
        lock (_lock)
        {
            if (_vote == null) { Send(client, "No hay ninguna votación en curso."); return; }
            RegisterVote(client, yes);
        }
    }

    // con _lock tomado
    private void RegisterVote(ACTcpClient client, bool yes)
    {
        var vote = _vote!;
        vote.Votes[client.SessionId] = yes;
        Send(client, yes ? $"Voto a favor registrado ({vote.Yes}/{vote.Needed})." : $"Voto en contra registrado ({vote.Yes}/{vote.Needed} a favor).");
        if (vote.Yes >= vote.Needed)
            Approve($"Aprobado ({vote.Yes}/{vote.Needed})");
        else if (vote.No > vote.ConnectedAtStart - vote.Needed)
        {
            // ya no puede salir: cerrarla antes de tiempo
            Broadcast($"Votación rechazada: {vote.No} en contra. Seguimos en {CurrentName()}.");
            _vote = null;
        }
    }

    // con _lock tomado
    private void Approve(string why)
    {
        var entry = _vote?.Entry ?? _pendingEntry!;
        _vote = null;
        _pendingEntry = entry;
        _pendingAt = DateTime.UtcNow.AddSeconds(_config.ChangeDelaySeconds);
        Broadcast($"{why}: {entry.Name}. Cambiando de circuito en {_config.ChangeDelaySeconds + _config.TransitionSeconds} s.");
        Log.Information("MapVote: aprobado {Name} ({Track}/{Layout})", entry.Name, entry.Track, entry.Layout);
    }

    internal void AdminSet(ACTcpClient client, int id)
    {
        lock (_lock)
        {
            if (_restarting) { Send(client, "Ya se está cambiando de circuito."); return; }
            if (!_catalog.TryGet(id, out var entry)) { Send(client, "Número no válido. Mira la lista con /maplist."); return; }
            _vote = null;
            _pendingEntry = entry;
            Approve("Cambio forzado por un administrador");
        }
    }

#if MAPVOTE_TEST
    internal string TestApply(int id)
    {
        lock (_lock)
        {
            if (!_catalog.TryGet(id, out var entry)) return "id no válido";
            _pendingEntry = entry;
            Approve("TEST");
            return "ok: " + entry.Name;
        }
    }
#endif

    internal void Cancel(ACTcpClient client)
    {
        lock (_lock)
        {
            if (_restarting) { Send(client, "Demasiado tarde: el servidor ya se está reiniciando."); return; }
            if (_vote == null && _pendingEntry == null) { Send(client, "No hay nada que cancelar."); return; }
            _vote = null;
            _pendingEntry = null;
            Broadcast("Votación o cambio cancelado por un administrador.");
        }
    }

    internal void SendList(ACTcpClient client, int page)
    {
        const int perPage = 8;
        var entries = _catalog.Entries;
        if (entries.Count == 0) { Send(client, "No hay circuitos instalados en el servidor."); return; }
        var pages = Math.Max(1, (int)Math.Ceiling(entries.Count / (double)perPage));
        page = Math.Clamp(page, 1, pages);
        Send(client, $"Circuitos {page}/{pages} (propón uno con /mapstart <número>):");
        foreach (var e in entries.Skip((page - 1) * perPage).Take(perPage))
            client.SendChatMessage($"  {e.Id} - {e.Name}");
        if (page < pages) client.SendChatMessage($"  Más: /maplist {page + 1}");
    }

    internal void SendStatus(ACTcpClient client)
    {
        lock (_lock)
        {
            Send(client, $"Ahora: {CurrentName()}");
            if (_pendingEntry != null)
                Send(client, $"Cambiando a {_pendingEntry.Name} en {Remaining(_pendingAt) + _config.TransitionSeconds} s.");
            else if (_vote != null)
                Send(client, $"Votación: {_vote.Entry.Name} · {_vote.Yes}/{_vote.Needed} a favor · {Remaining(_vote.EndsAt)} s.");
            else if (DateTime.UtcNow < _nextAllowedStart)
                Send(client, $"Próxima votación posible en {Remaining(_nextAllowedStart)} s.");
        }
    }

    internal void Reload(ACTcpClient client)
    {
        _catalog.Reload();
        Send(client, $"Lista recargada: {_catalog.Entries.Count} circuitos.");
    }

    // ------------------------------------------------------------------ estado para el menú (HTTP)
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
                changing = _pendingEntry != null || _restarting,
                changingTo = _pendingEntry?.Name,
                changeInSeconds = _pendingEntry == null ? 0 : Remaining(_pendingAt) + _config.TransitionSeconds,
                voteDurationSeconds = _config.VoteDurationSeconds
            };
        }
    }

    // ------------------------------------------------------------------ bucle de control
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            TrackEntry? toApply = null;
            try
            {
                lock (_lock)
                {
                    var now = DateTime.UtcNow;
                    if (_vote != null && now >= _vote.EndsAt)
                    {
                        Broadcast($"Votación rechazada: {_vote.Yes}/{_vote.Needed} votos a favor. Seguimos en {CurrentName()}.");
                        _vote = null;
                    }

                    if (_pendingEntry != null && now >= _pendingAt && !_restarting)
                    {
                        toApply = _pendingEntry;
                        _pendingEntry = null;
                        _restarting = true;
                    }
                }

                if (toApply != null)
                    await ApplyChangeAsync(toApply, stoppingToken);
            }
            catch (OperationCanceledException) { break; }
            catch (Exception ex)
            {
                Log.Error(ex, "MapVote: error en el bucle de control");
                lock (_lock) _restarting = false;
            }

            try { await Task.Delay(500, stoppingToken); }
            catch (OperationCanceledException) { break; }
        }
    }

    // ------------------------------------------------------------------ cambio de circuito
    private static readonly Regex TrackLine = new(@"^\s*TRACK\s*=.*$", RegexOptions.Multiline | RegexOptions.IgnoreCase);
    private static readonly Regex LayoutLine = new(@"^\s*CONFIG_TRACK\s*=.*$", RegexOptions.Multiline | RegexOptions.IgnoreCase);
    private static readonly Regex ServerSection = new(@"^\s*\[SERVER\]\s*$", RegexOptions.Multiline | RegexOptions.IgnoreCase);

    private static void WriteTrack(string serverCfgPath, string track, string layout)
    {
        var text = File.ReadAllText(serverCfgPath);
        text = TrackLine.IsMatch(text) ? TrackLine.Replace(text, $"TRACK={track}", 1) : InsertInServer(text, $"TRACK={track}");
        text = LayoutLine.IsMatch(text) ? LayoutLine.Replace(text, $"CONFIG_TRACK={layout}", 1) : InsertInServer(text, $"CONFIG_TRACK={layout}");
        var tmp = serverCfgPath + ".tmp";
        File.WriteAllText(tmp, text);
        File.Move(tmp, serverCfgPath, true);
    }

    private static string InsertInServer(string text, string line)
    {
        var m = ServerSection.Match(text);
        return m.Success ? text.Insert(m.Index + m.Length, "\n" + line) : $"[SERVER]\n{line}\n" + text;
    }

    private async Task ApplyChangeAsync(TrackEntry entry, CancellationToken token)
    {
        // Se escribe el nombre de carpeta tal cual: AssettoServer añade él mismo el prefijo "csp/<versión>/../"
        var newTrack = entry.Track;

        // Nunca se modifica un preset: el cambio va a la configuración de arranque (cfg/).
        // Si ahora mismo está en pista un preset (lo cargó la votación entre presets), se copia
        // su server_cfg.ini a cfg/ para conservar su clima y reglas, y se reinicia desde cfg/.
        var startupCfg = Path.GetFullPath(Path.Join("cfg", "server_cfg.ini"));
        var runningCfg = Path.GetFullPath(Path.Join(_serverConfig.BaseFolder, "server_cfg.ini"));
        var fromPreset = !string.Equals(startupCfg, runningCfg, StringComparison.Ordinal);
        if (fromPreset && File.Exists(runningCfg))
        {
            File.Copy(runningCfg, startupCfg + ".tmp", true);
            File.Move(startupCfg + ".tmp", startupCfg, true);
            Log.Information("MapVote: copiado {From} a cfg/ (el preset no se modifica)", runningCfg);
        }

        var targets = new List<string> { startupCfg };
        if (_config.ApplyToAllPresets)
        {
            targets.Add(Path.Join("cfg", "server_cfg.ini"));
            if (Directory.Exists("presets"))
                targets.AddRange(Directory.GetDirectories("presets").Select(d => Path.Join(d, "server_cfg.ini")));
        }

        foreach (var path in targets.Select(Path.GetFullPath).Distinct().Where(File.Exists))
        {
            WriteTrack(path, newTrack, entry.Layout);
            Log.Information("MapVote: {Path} -> {Track} / '{Layout}'", path, newTrack, entry.Layout);
        }

        if (_serverConfig.Extra.EnableClientMessages && _config.EnableReconnect)
        {
            Broadcast($"Cargando {entry.Name}: te reconectamos solo en {_config.TransitionSeconds} s.");
            _entryCarManager.BroadcastPacket(new MapVoteReconnectPacket { Time = (ushort)_config.TransitionSeconds });
        }
        else
        {
            Broadcast($"Cargando {entry.Name}: el servidor se reinicia, vuelve a entrar en unos segundos.");
            await Task.Delay(1500, token);
            _entryCarManager.BroadcastPacket(new CSPKickBanMessageOverride { Message = KickReasonText });
            _entryCarManager.BroadcastPacket(new KickCar { SessionId = 255, Reason = KickReason.Kicked });
        }

        // El reinicio va 1 s antes de que el script del cliente se reconecte
        await Task.Delay(Math.Max(1, _config.TransitionSeconds - 1) * 1000, token);
        Log.Information("MapVote: reiniciando el servidor con {Name}", entry.Name);
        Program.RestartServer(
            fromPreset ? null : _serverConfig.Preset,
            portOverrides: new PortOverrides
            {
                TcpPort = _serverConfig.Server.TcpPort,
                UdpPort = _serverConfig.Server.UdpPort,
                HttpPort = _serverConfig.Server.HttpPort
            });
    }
}
