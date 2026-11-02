using System.Reflection;
using System.Text.RegularExpressions;
using AssettoServer;
using AssettoServer.Network.Tcp;
using AssettoServer.Server;
using AssettoServer.Server.Configuration;
using AssettoServer.Shared.Network.Packets.Outgoing;
using Microsoft.Extensions.Hosting;
using Serilog;

namespace AcsDriftServerPlugin;

/// <summary>
/// Servicios de servidor para el menú ACS Drift: API de coches y presets, estado de administrador,
/// votación pública de circuito y acciones administrativas. Los cambios se aplican reiniciando
/// AssettoServer dentro del mismo proceso.
/// </summary>
public class AcsDriftServerPlugin : BackgroundService
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

    private const string Tag = "[Map]";
    private const string PresetKickReasonText = "PRESET CHANGE: rejoin through Content Manager and choose a car";

    private readonly MapVoteConfiguration _config;
    private readonly ACServerConfiguration _serverConfig;
    private readonly EntryCarManager _entryCarManager;
    private readonly TrackCatalog _catalog;
    private readonly PresetCatalog _presetCatalog;

    private readonly object _lock = new();
    private VoteState? _vote;
    private TrackEntry? _pendingEntry;
    private PresetEntry? _pendingPreset;
    private DateTime _pendingAt;
    private DateTime _nextAllowedStart = DateTime.MinValue;
    private bool _restarting;

    public AcsDriftServerPlugin(MapVoteConfiguration config,
        ACServerConfiguration serverConfig,
        EntryCarManager entryCarManager,
        TrackCatalog catalog,
        PresetCatalog presetCatalog,
        CSPServerScriptProvider scriptProvider,
        CSPClientMessageTypeManager clientMessageTypeManager,
        CSPFeatureManager cspFeatureManager)
    {
        _config = config;
        _serverConfig = serverConfig;
        _entryCarManager = entryCarManager;
        _catalog = catalog;
        _presetCatalog = presetCatalog;

        if (serverConfig.Extra.EnableClientMessages)
        {
            // Menú del juego y reconexión automática
            var luaPath = Path.Join(Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location), "lua", "mapvote.lua");
            if (File.Exists(luaPath))
                scriptProvider.AddScript(File.ReadAllText(luaPath), "mapvote.lua");
            else
                Log.Warning("ACS Drift Server: {Path} not found; only chat commands will be available", luaPath);

            clientMessageTypeManager.RegisterOnlineEvent<MapVoteActionPacket>(OnAction);
            clientMessageTypeManager.RegisterOnlineEvent<AdminStatusRequestPacket>(OnAdminStatusRequest);
            clientMessageTypeManager.RegisterOnlineEvent<AdminPresetChangePacket>(OnAdminPresetChange);
            // VotingPresetPlugin también la declara y añadirla dos veces rompe el arranque:
            // si ese plugin está activado, se la dejamos a él.
            var votingPreset = serverConfig.Extra.EnablePlugins?.Any(p =>
                string.Equals(p, "VotingPresetPlugin", StringComparison.OrdinalIgnoreCase)) == true;
            if (!votingPreset)
            {
                try { cspFeatureManager.Add(new CSPFeature { Name = "FREQUENT_TRACK_CHANGES" }); }
                catch (ArgumentException) { Log.Debug("ACS Drift Server: FREQUENT_TRACK_CHANGES already declared by another plugin"); }
            }
        }
        else
        {
            Log.Warning("ACS Drift Server: EnableClientMessages is disabled in extra_cfg.yml: " +
                        "the menu and automatic reconnect will be unavailable; only chat commands will work");
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

    // ACTcpClient.IsAdministrator (comprobado en 0.0.55-pre45) es lo que mira [RequireAdmin], p.ej. /mapset.
    // Solo sirve para que el menú muestre u oculte opciones: los comandos de admin lo siguen comprobando.
    // Se responde solo a quien pregunta, nunca por broadcast.
    private static void OnAdminStatusRequest(ACTcpClient client, AdminStatusRequestPacket packet)
    {
        client.SendPacket(new AdminStatusResponsePacket
        {
            IsAdmin = client.IsAdministrator ? (byte)1 : (byte)0
        });
    }

    private void OnAdminPresetChange(ACTcpClient client, AdminPresetChangePacket packet)
    {
        if (!client.IsAdministrator)
        {
            Send(client, "This action requires administrator privileges.");
            return;
        }

        AdminSetPreset(client, packet.PresetId);
    }

    // ------------------------------------------------------------------ acciones de jugador
    internal void StartVote(ACTcpClient client, int id)
    {
        lock (_lock)
        {
            if (_pendingEntry != null || _pendingPreset != null || _restarting) { Send(client, "A track or preset change is already in progress."); return; }
            if (_vote != null) { Send(client, "A vote is already in progress. Vote with /mapyes or /mapno."); return; }

            var now = DateTime.UtcNow;
            if (now < _nextAllowedStart) { Send(client, $"Wait {Remaining(_nextAllowedStart)} s before proposing another track."); return; }
            if (!_catalog.TryGet(id, out var entry)) { Send(client, "Invalid number. Check the list with /maplist."); return; }

            var (curTrack, curLayout) = CurrentTrack;
            if (string.Equals(entry.Track, curTrack, StringComparison.OrdinalIgnoreCase) &&
                string.Equals(entry.Layout, curLayout, StringComparison.OrdinalIgnoreCase))
            {
                Send(client, "You are already on that track.");
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

            Broadcast($"{_vote.ProposerName} proposes: {entry.Name}. {_vote.Needed} of {connected} votes in favor are required. " +
                      $"Vote with /mapyes or /mapno ({_config.VoteDurationSeconds} s).");

            if (_config.ProposerVotesYes)
                RegisterVote(client, true);
        }
    }

    internal void CastVote(ACTcpClient client, bool yes)
    {
        lock (_lock)
        {
            if (_vote == null) { Send(client, "There is no vote in progress."); return; }
            RegisterVote(client, yes);
        }
    }

    // con _lock tomado
    private void RegisterVote(ACTcpClient client, bool yes)
    {
        var vote = _vote!;
        vote.Votes[client.SessionId] = yes;
        Send(client, yes ? $"Vote in favor recorded ({vote.Yes}/{vote.Needed})." : $"Vote against recorded ({vote.Yes}/{vote.Needed} in favor).");
        if (vote.Yes >= vote.Needed)
            Approve($"Aprobado ({vote.Yes}/{vote.Needed})");
        else if (vote.No > vote.ConnectedAtStart - vote.Needed)
        {
            // ya no puede salir: cerrarla antes de tiempo
            Broadcast($"Vote rejected: {vote.No} against. Staying on {CurrentName()}.");
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
        Broadcast($"{why}: {entry.Name}. Track changes in {_config.ChangeDelaySeconds + _config.TransitionSeconds} s.");
        Log.Information("ACS Drift Server: approved {Name} ({Track}/{Layout})", entry.Name, entry.Track, entry.Layout);
    }

    internal void AdminSet(ACTcpClient client, int id)
    {
        lock (_lock)
        {
            if (_restarting || _pendingEntry != null || _pendingPreset != null) { Send(client, "A track or preset change is already in progress."); return; }
            if (!_catalog.TryGet(id, out var entry)) { Send(client, "Invalid number. Check the list with /maplist."); return; }
            _vote = null;
            _pendingEntry = entry;
            Approve("Change forced by an administrator");
        }
    }

    internal void AdminSetPreset(ACTcpClient client, int id)
    {
        lock (_lock)
        {
            if (!client.IsAdministrator)
            {
                Send(client, "This action requires administrator privileges.");
                return;
            }
            if (_restarting || _pendingEntry != null || _pendingPreset != null)
            {
                Send(client, "A change is already in progress.");
                return;
            }
            if (!_presetCatalog.TryGet(id, out var preset))
            {
                Send(client, "Invalid preset. Reload the menu and try again.");
                return;
            }
            if (preset.IsCurrent)
            {
                Send(client, "That preset is already active.");
                return;
            }

            _vote = null;
            _pendingPreset = preset;
            _pendingAt = DateTime.UtcNow.AddSeconds(_config.ChangeDelaySeconds);
            var totalSeconds = _config.ChangeDelaySeconds + _config.TransitionSeconds;
            Broadcast($"An administrator is switching to preset {preset.Name}. The server will restart in {totalSeconds} s.");
            Log.Information("ACS Drift Server: preset change to {Name} scheduled", preset.Name);
        }
    }

#if MAPVOTE_TEST
    internal string TestPreset(int id)
    {
        lock (_lock)
        {
            if (!_presetCatalog.TryGet(id, out var preset)) return "invalid id";
            _pendingPreset = preset;
            _pendingAt = DateTime.UtcNow.AddSeconds(_config.ChangeDelaySeconds);
            return "ok: " + preset.Name;
        }
    }

    internal string TestApply(int id)
    {
        lock (_lock)
        {
            if (!_catalog.TryGet(id, out var entry)) return "invalid id";
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
            if (_restarting) { Send(client, "Too late: the server is already restarting."); return; }
            if (_vote == null && _pendingEntry == null && _pendingPreset == null) { Send(client, "There is nothing to cancel."); return; }
            _vote = null;
            _pendingEntry = null;
            _pendingPreset = null;
            Broadcast("Vote or change cancelled by an administrator.");
        }
    }

    internal void SendList(ACTcpClient client, int page)
    {
        const int perPage = 8;
        var entries = _catalog.Entries;
        if (entries.Count == 0) { Send(client, "No tracks are installed on the server."); return; }
        var pages = Math.Max(1, (int)Math.Ceiling(entries.Count / (double)perPage));
        page = Math.Clamp(page, 1, pages);
        Send(client, $"Tracks {page}/{pages} (propose one with /mapstart <number>):");
        foreach (var e in entries.Skip((page - 1) * perPage).Take(perPage))
            client.SendChatMessage($"  {e.Id} - {e.Name}");
        if (page < pages) client.SendChatMessage($"  More: /maplist {page + 1}");
    }

    internal void SendStatus(ACTcpClient client)
    {
        lock (_lock)
        {
            Send(client, $"Current track: {CurrentName()}");
            if (_pendingEntry != null)
                Send(client, $"Changing to {_pendingEntry.Name} in {Remaining(_pendingAt) + _config.TransitionSeconds} s.");
            else if (_vote != null)
                Send(client, $"Vote: {_vote.Entry.Name} · {_vote.Yes}/{_vote.Needed} in favor · {Remaining(_vote.EndsAt)} s.");
            else if (DateTime.UtcNow < _nextAllowedStart)
                Send(client, $"Another vote can be started in {Remaining(_nextAllowedStart)} s.");
        }
    }

    internal void Reload(ACTcpClient client)
    {
        _catalog.Reload();
        Send(client, $"Track list reloaded: {_catalog.Entries.Count} tracks.");
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
                changing = _pendingEntry != null || _pendingPreset != null || _restarting,
                changingTo = _pendingEntry?.Name ?? _pendingPreset?.Name,
                changeInSeconds = _pendingEntry == null && _pendingPreset == null
                    ? 0
                    : Remaining(_pendingAt) + _config.TransitionSeconds,
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
            PresetEntry? presetToApply = null;
            try
            {
                lock (_lock)
                {
                    var now = DateTime.UtcNow;
                    if (_vote != null && now >= _vote.EndsAt)
                    {
                        Broadcast($"Vote rejected: {_vote.Yes}/{_vote.Needed} votes in favor. Staying on {CurrentName()}.");
                        _vote = null;
                    }

                    if (_pendingEntry != null && now >= _pendingAt && !_restarting)
                    {
                        toApply = _pendingEntry;
                        _pendingEntry = null;
                        _restarting = true;
                    }
                    else if (_pendingPreset != null && now >= _pendingAt && !_restarting)
                    {
                        presetToApply = _pendingPreset;
                        _pendingPreset = null;
                        _restarting = true;
                    }
                }

                if (toApply != null)
                    await ApplyChangeAsync(toApply, stoppingToken);
                else if (presetToApply != null)
                    await ApplyPresetChangeAsync(presetToApply, stoppingToken);
            }
            catch (OperationCanceledException) { break; }
            catch (Exception ex)
            {
                Log.Error(ex, "ACS Drift Server: error in control loop");
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
            // y sus coches: cada preset puede tener los suyos
            var runningEntry = Path.Join(_serverConfig.BaseFolder, "entry_list.ini");
            var startupEntry = Path.Join("cfg", "entry_list.ini");
            if (File.Exists(runningEntry))
            {
                File.Copy(runningEntry, startupEntry + ".tmp", true);
                File.Move(startupEntry + ".tmp", startupEntry, true);
            }
            Log.Information("ACS Drift Server: copied {From} to cfg/ (the preset is not modified)", _serverConfig.BaseFolder);
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
            Log.Information("ACS Drift Server: {Path} -> {Track} / '{Layout}'", path, newTrack, entry.Layout);
        }

        await NotifyAndRestartAsync(entry.Name, fromPreset ? null : _serverConfig.Preset, token);
    }

    private async Task ApplyPresetChangeAsync(PresetEntry preset, CancellationToken token)
    {
        Broadcast($"Switching to preset {preset.Name}: the server will restart in {_config.TransitionSeconds} s. " +
                  "Wait in Content Manager, then rejoin and choose a car from the new list.");
        await Task.Delay(_config.TransitionSeconds * 1000, token);

        var clients = _entryCarManager.ConnectedCars.Values
            .Select(car => car.Client)
            .Where(client => client != null)
            .ToArray();
        foreach (var client in clients)
        {
            await _entryCarManager.KickAsync(
                client,
                KickReason.Kicked,
                "preset change",
                PresetKickReasonText);
        }

        await RestartAsync(preset.Name, preset.Folder, 1, token);
    }

    private async Task NotifyAndRestartAsync(string name, string? preset, CancellationToken token)
    {
        if (_serverConfig.Extra.EnableClientMessages && _config.EnableReconnect)
        {
            Broadcast($"Loading {name}: you will be reconnected in {_config.TransitionSeconds} s.");
            _entryCarManager.BroadcastPacket(new MapVoteReconnectPacket { Time = (ushort)_config.TransitionSeconds });
        }
        else
        {
            // Do not broadcast KickCar with SessionId 255: it can crash the client.
            // Players disconnect when the server restarts.
            Broadcast($"Loading {name}: the server is restarting. Please rejoin in a few seconds.");
        }

        await RestartAsync(name, preset, Math.Max(1, _config.TransitionSeconds - 1), token);
    }

    private async Task RestartAsync(string name, string? preset, int delaySeconds, CancellationToken token)
    {
        await Task.Delay(delaySeconds * 1000, token);
        Log.Information("ACS Drift Server: restarting server with {Name}", name);
        Program.RestartServer(
            preset,
            portOverrides: new PortOverrides
            {
                TcpPort = _serverConfig.Server.TcpPort,
                UdpPort = _serverConfig.Server.UdpPort,
                HttpPort = _serverConfig.Server.HttpPort
            });
    }
}
