using System.Numerics;
using AssettoServer.Network.Tcp;
using AssettoServer.Server;
using AssettoServer.Server.Configuration;
using AssettoServer.Shared.Network.Packets.Outgoing;
using Microsoft.Extensions.Hosting;
using Serilog;

namespace AcsDriftServerPlugin;

/// <summary>
/// Fantasma: reproduce una pasada grabada como un coche más. Solo hay uno a la vez (cargar otro lo
/// sobrescribe) y solo lo usan administradores. Ocupa una plaza libre del modelo grabado: el servidor
/// anuncia ese slot con CarConnected y le envía posiciones por UDP a los clientes que ya han recibido
/// su primera actualización.
/// </summary>
public class GhostService : BackgroundService
{
    private sealed class ActiveGhost
    {
        public required GhostMeta Meta { get; init; }
        public required GhostSample[] Samples { get; init; }
        public required EntryCar Slot { get; init; }
        public required long StartTick { get; init; }
        // null = todavía no se ha enviado la visibilidad a los clientes
        public bool? Visible { get; set; }
    }

    private const string Tag = "[Ghost]";
    // A validar: unidades de PositionUpdateIn.Rotation (grados o radianes).
    private const float AngleWrap = 360f;
    // Profundidad a la que se manda el fantasma mientras está oculto (queda fuera del circuito).
    private const float HideDepth = 1000f;
    // Cuántos paquetes de posición se mandan antes de mostrarlo, para que no aparezca "deslizándose".
    private const int SpawnRepeats = 3;
    private const int MinSamples = 10;

    // Estados que recibe el menú (ACP_GhostState.state)
    private const byte StateIdle = 0;
    private const byte StateRecording = 1;
    private const byte StateSaved = 2;
    private const byte StateError = 3;

    // Códigos de error (ACP_GhostState.code)
    private const byte ErrNotAdmin = 1;
    private const byte ErrNoCar = 2;
    private const byte ErrAlreadyRecording = 3;
    private const byte ErrTooShort = 4;
    private const byte ErrNoSlot = 5;
    private const byte ErrNotFound = 6;
    private const byte ErrNotRecording = 7;

    private readonly MapVoteConfiguration _config;
    private readonly ACServerConfiguration _serverConfig;
    private readonly EntryCarManager _entryCarManager;

    private readonly object _lock = new();
    private GhostRecorder? _recorder;
    private string _recAuthor = "";
    private ulong _recAuthorGuid;
    private string _recCar = "";
    private string _recSkin = "";
    private ActiveGhost? _active;
    private readonly HashSet<ACTcpClient> _announced = new();
    private byte _pakSequence;

    public GhostService(MapVoteConfiguration config,
        ACServerConfiguration serverConfig,
        EntryCarManager entryCarManager,
        CSPClientMessageTypeManager clientMessageTypeManager)
    {
        _config = config;
        _serverConfig = serverConfig;
        _entryCarManager = entryCarManager;

        if (serverConfig.Extra.EnableClientMessages)
            clientMessageTypeManager.RegisterOnlineEvent<GhostActionPacket>(OnAction);

        entryCarManager.ClientConnected += OnClientConnected;
    }

    // ------------------------------------------------------------------ utilidades
    private static void Send(ACTcpClient client, string message) => client.SendChatMessage($"{Tag} {message}");
    private void Broadcast(string message) => _entryCarManager.BroadcastChat($"{Tag} {message}");

    private static void SendState(ACTcpClient client, byte state, int seconds, byte code, int id)
    {
        try
        {
            client.SendPacket(new GhostStatePacket
            {
                State = state,
                Seconds = (ushort)Math.Clamp(seconds, 0, ushort.MaxValue),
                Code = code,
                Id = (ushort)Math.Clamp(id, 0, ushort.MaxValue)
            });
        }
        catch (Exception ex) { Log.Debug(ex, "ACS Drift Server: could not send ghost state to {Name}", client.Name); }
    }

    private static void Fail(ACTcpClient client, byte code, string message)
    {
        SendState(client, StateError, 0, code, 0);
        Send(client, message);
    }

    private static bool IsAdmin(ACTcpClient client)
    {
        if (client.IsAdministrator) return true;
        Fail(client, ErrNotAdmin, "This action requires administrator privileges.");
        return false;
    }

    private IEnumerable<ACTcpClient> ConnectedClients()
        => _entryCarManager.ConnectedCars.Values.Select(c => c.Client).OfType<ACTcpClient>();

    private EntryCar? CarOf(ACTcpClient client)
        => _entryCarManager.ConnectedCars.Values.FirstOrDefault(c => c.Client == client);

    private string CurrentFolder()
    {
        var (track, layout) = AcsDriftServerPlugin.TrackOf(_serverConfig);
        return GhostFile.Folder(_config.GhostsFolder, track, layout);
    }

    // Plaza libre del modelo. Si el fantasma actual usa esa plaza, también cuenta como libre
    // (no está ocupada por un cliente), así que se puede sobrescribir aunque sea la única.
    private EntryCar? FindFreeSlot(string model)
        => _entryCarManager.EntryCars.FirstOrDefault(c => c.Model == model && c.Client == null && !c.AiControlled);

    // ------------------------------------------------------------------ eventos de conexión
    private void OnClientConnected(ACTcpClient client, EventArgs args)
        => client.FirstUpdateSent += OnFirstUpdateSent;

    private void OnFirstUpdateSent(ACTcpClient client, EventArgs args)
    {
        // Un cliente que entra con un fantasma cargado lo recibe desde su primera actualización.
        lock (_lock)
        {
            if (_active == null) return;
            Announce(client, _active);
            _announced.Add(client);
        }
    }

    // ------------------------------------------------------------------ menú (online event)
    private void OnAction(ACTcpClient client, GhostActionPacket packet)
    {
        switch (packet.Action)
        {
            case 1: StartRecording(client); break;
            case 2: StopRecording(client); break;
            case 3: CancelRecording(client); break;
            case 4: Load(client, packet.Id); break;
            case 5: Unload(client); break;
            case 6: Delete(client, packet.Id); break;
        }
    }

    // ------------------------------------------------------------------ grabación
    internal void StartRecording(ACTcpClient client)
    {
        if (!IsAdmin(client)) return;
        lock (_lock)
        {
            if (_recorder != null) { Fail(client, ErrAlreadyRecording, "A ghost is already being recorded."); return; }

            var car = CarOf(client);
            if (car == null) { Fail(client, ErrNoCar, "You need to be connected with a car to record a ghost."); return; }

            _recorder = new GhostRecorder(car, _config.GhostMaxRecordSeconds);
            _recAuthor = client.Name ?? "?";
            _recAuthorGuid = client.Guid;
            _recCar = car.Model;
            _recSkin = car.Skin;
            SendState(client, StateRecording, 0, 0, 0);
            Broadcast($"{_recAuthor} is recording a ghost lap.");
            Log.Information("ACS Drift Server: ghost recording started by {Name} ({Car})", _recAuthor, _recCar);
        }
    }

    internal void StopRecording(ACTcpClient client)
    {
        if (!IsAdmin(client)) return;
        lock (_lock)
        {
            if (_recorder == null) { Fail(client, ErrNotRecording, "There is no ghost recording in progress."); return; }
            FinishRecordingLocked(client);
        }
    }

    internal void CancelRecording(ACTcpClient client)
    {
        if (!IsAdmin(client)) return;
        lock (_lock)
        {
            if (_recorder == null) { Fail(client, ErrNotRecording, "There is no ghost recording in progress."); return; }
            _recorder.Stop();
            _recorder = null;
            SendState(client, StateIdle, 0, 0, 0);
            Send(client, "Ghost recording cancelled.");
        }
    }

    // con _lock tomado. notify = a quién mandar el resultado (null = solo aviso en el chat del servidor)
    private void FinishRecordingLocked(ACTcpClient? notify)
    {
        var recorder = _recorder!;
        _recorder = null;
        var samples = recorder.Stop();

        if (samples.Length < MinSamples || samples[^1].TimeMs < 1000)
        {
            if (notify != null) Fail(notify, ErrTooShort, "The recording is too short to be saved.");
            else Broadcast("Ghost recording discarded: it is too short.");
            return;
        }

        var meta = new GhostMeta
        {
            Name = $"{_recAuthor} - {_recCar}",
            Car = _recCar,
            Skin = _recSkin,
            Author = _recAuthor,
            AuthorGuid = _recAuthorGuid,
            DurationMs = (int)samples[^1].TimeMs,
            Created = DateTime.UtcNow
        };
        var saved = GhostFile.Save(CurrentFolder(), meta, samples);
        var seconds = saved.DurationMs / 1000;

        if (notify != null) SendState(notify, StateSaved, seconds, 0, saved.Id);
        Broadcast($"Ghost saved: {saved.Author} · {saved.Car} · {seconds} s (id {saved.Id}).");
        Log.Information("ACS Drift Server: ghost {Id} saved ({Car}, {Seconds} s)", saved.Id, saved.Car, seconds);
    }

    // ------------------------------------------------------------------ fantasma activo
    internal void Load(ACTcpClient client, int id)
    {
        if (!IsAdmin(client)) return;
        lock (_lock)
        {
            var loaded = GhostFile.Load(CurrentFolder(), id);
            if (loaded == null) { Fail(client, ErrNotFound, "That ghost does not exist on this layout."); return; }
            var (meta, samples) = loaded.Value;

            var slot = FindFreeSlot(meta.Car);
            if (slot == null)
            {
                Fail(client, ErrNoSlot, $"There is no free {meta.Car} slot on the server. Free one first.");
                return;
            }

            // Sobrescribe el fantasma anterior (solo puede haber uno).
            ReleaseLocked();
            _active = new ActiveGhost
            {
                Meta = meta,
                Samples = samples,
                Slot = slot,
                StartTick = Environment.TickCount64
            };
            foreach (var c in ConnectedClients())
            {
                Announce(c, _active);
                _announced.Add(c);
            }

            SendState(client, StateIdle, 0, 0, meta.Id);
            Broadcast($"Ghost loaded: {meta.Author} · {meta.Car} · {meta.DurationMs / 1000} s.");
            Log.Information("ACS Drift Server: ghost {Id} loaded in slot {Slot}", meta.Id, slot.SessionId);
        }
    }

    internal void Unload(ACTcpClient client)
    {
        if (!IsAdmin(client)) return;
        lock (_lock)
        {
            if (_active == null) { Fail(client, ErrNotFound, "There is no ghost loaded."); return; }
            ReleaseLocked();
            SendState(client, StateIdle, 0, 0, 0);
            Broadcast("Ghost removed.");
        }
    }

    internal void Delete(ACTcpClient client, int id)
    {
        if (!IsAdmin(client)) return;
        lock (_lock)
        {
            if (!GhostFile.Delete(CurrentFolder(), id)) { Fail(client, ErrNotFound, "That ghost does not exist on this layout."); return; }
            if (_active?.Meta.Id == id) ReleaseLocked();
            SendState(client, StateIdle, 0, 0, 0);
            Send(client, $"Ghost {id} deleted.");
        }
    }

    internal void SendList(ACTcpClient client)
    {
        if (!IsAdmin(client)) return;
        lock (_lock)
        {
            var list = GhostFile.List(CurrentFolder());
            if (list.Count == 0) { Send(client, "No ghosts saved for this layout."); return; }

            Send(client, "Ghosts for this layout (load one with /ghostplay <id>):");
            foreach (var g in list)
                client.SendChatMessage($"  {g.Id} - {g.Author} · {g.Car} · {g.DurationMs / 1000} s" +
                                       (g.Id == _active?.Meta.Id ? " (loaded)" : ""));
        }
    }

    // con _lock tomado
    private void ReleaseLocked()
    {
        if (_active == null) return;
        var slot = _active.Slot.SessionId;
        _active = null;
        foreach (var c in _announced)
        {
            try { c.SendPacket(new CarDisconnected { SessionId = slot }); }
            catch (Exception ex) { Log.Debug(ex, "ACS Drift Server: could not remove ghost from {Name}", c.Name); }
        }
        _announced.Clear();
    }

    private static void Announce(ACTcpClient client, ActiveGhost g)
    {
        Log.Information("{Tag} Announce slot {Slot} to {Name}, visible={Visible}",
            Tag, g.Slot.SessionId, client.Name, g.Visible);
        try
        {
            client.SendPacket(new CarConnected
            {
                SessionId = g.Slot.SessionId,
                Name = $"Ghost - {g.Meta.Author}",
                Nation = ""
            });
            client.SendPacket(new CSPCarVisibilityUpdate
            {
                SessionId = g.Slot.SessionId,
                Visible = g.Visible == true ? CSPCarVisibility.Visible : CSPCarVisibility.Invisible
            });
        }
        catch (Exception ex) { Log.Debug(ex, "ACS Drift Server: could not announce ghost to {Name}", client.Name); }
    }

    // ------------------------------------------------------------------ estado para el menú (HTTP)
    internal object GetStatus()
    {
        lock (_lock)
        {
            var a = _active;
            return new
            {
                recording = _recorder != null,
                recordingSeconds = _recorder == null ? 0 : _recorder.ElapsedMs / 1000,
                active = a != null,
                ghost = a == null ? null : new
                {
                    id = a.Meta.Id,
                    name = a.Meta.Name,
                    author = a.Meta.Author,
                    car = a.Meta.Car,
                    durationMs = a.Meta.DurationMs,
                    slot = a.Slot.SessionId
                }
            };
        }
    }

    internal int? ActiveId
    {
        get { lock (_lock) return _active?.Meta.Id; }
    }

    internal List<GhostMeta> ListSaved()
    {
        lock (_lock) return GhostFile.List(CurrentFolder());
    }

    /// <summary>Lo usa GhostSlotFilter: un slot reservado por el fantasma no lo puede ocupar nadie.</summary>
    internal bool IsGhostSlot(byte sessionId)
    {
        lock (_lock) return _active != null && _active.Slot.SessionId == sessionId;
    }

    // ------------------------------------------------------------------ bucle de control
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var interval = TimeSpan.FromMilliseconds(1000.0 / Math.Clamp(_config.GhostPlaybackHz, 10, 100));
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                lock (_lock) Tick();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "ACS Drift Server: error in ghost loop");
            }

            try { await Task.Delay(interval, stoppingToken); }
            catch (OperationCanceledException) { break; }
        }
    }

    // con _lock tomado
    private void Tick()
    {
        var connected = new HashSet<ACTcpClient>(ConnectedClients());
        _announced.RemoveWhere(c => !connected.Contains(c));

        if (_recorder != null)
        {
            if (_recorder.Full)
            {
                Broadcast("The ghost recording reached its maximum length.");
                FinishRecordingLocked(null);
            }
            else if (_recorder.Car.Client == null)
            {
                Broadcast("The player left during the ghost recording.");
                FinishRecordingLocked(null);
            }
        }

        var g = _active;
        if (g == null || g.Meta.DurationMs <= 0) return;

        // Pasada + pausa entre vueltas; el fantasma vuelve a empezar desde el principio de la pasada.
        var cycle = g.Meta.DurationMs + _config.GhostLoopGapSeconds * 1000L;
        var elapsed = (Environment.TickCount64 - g.StartTick) % cycle;

        if (elapsed < g.Meta.DurationMs)
        {
            if (g.Visible != true) Show(g, elapsed);
            SendPose(g, Interpolate(g.Samples, elapsed));
        }
        else if (g.Visible != false)
        {
            Hide(g, elapsed);
        }
    }

    // Aparecer en el punto de inicio: unos paquetes ya ahí y luego se muestra.
    private void Show(ActiveGhost g, long elapsed)
    {
        Log.Information("{Tag} Show slot {Slot} elapsed={Elapsed} ms, duration={Duration} ms, announced={Count}",
            Tag, g.Slot.SessionId, elapsed, g.Meta.DurationMs, _announced.Count);
        var first = g.Samples[0];
        for (var i = 0; i < SpawnRepeats; i++) SendPose(g, first);
        SendVisibility(g, CSPCarVisibility.Visible);
        g.Visible = true;
    }

    // Ocultarlo y mandarlo bajo el circuito para que no quede un obstáculo invisible en la pausa.
    private void Hide(ActiveGhost g, long elapsed)
    {
        Log.Information("{Tag} Hide slot {Slot} elapsed={Elapsed} ms, duration={Duration} ms, announced={Count}",
            Tag, g.Slot.SessionId, elapsed, g.Meta.DurationMs, _announced.Count);
        SendVisibility(g, CSPCarVisibility.Invisible);
        var far = g.Samples[0];
        far.Position = new Vector3(far.Position.X, far.Position.Y - HideDepth, far.Position.Z);
        for (var i = 0; i < SpawnRepeats; i++) SendPose(g, far);
        g.Visible = false;
    }

    private void SendPose(ActiveGhost g, GhostSample s)
    {
        var seq = _pakSequence++;
        var now = Environment.TickCount64;
        foreach (var client in _announced)
        {
            try
            {
                // Mismo cálculo que EntryCar.GetPositionUpdateForCar: timestamp del servidor menos el offset del receptor.
                var offset = CarOf(client)?.TimeOffset ?? 0;
                var timestamp = unchecked((uint)(now - offset));
                var packet = new PositionUpdateOut(g.Slot.SessionId, seq, timestamp, 0,
                    s.Position, s.Rotation, s.Velocity,
                    s.TyreFL, s.TyreFR, s.TyreRL, s.TyreRR,
                    s.SteerAngle, s.WheelAngle, s.EngineRpm, s.Gear,
                    (CarStatusFlags)s.StatusFlag, s.PerformanceDelta, s.Gas);
                client.SendPacketUdp(in packet);
            }
            catch (Exception ex) { Log.Debug(ex, "ACS Drift Server: could not send ghost position to {Name}", client.Name); }
        }
    }

    private void SendVisibility(ActiveGhost g, CSPCarVisibility visible)
    {
        foreach (var client in _announced)
        {
            try { client.SendPacket(new CSPCarVisibilityUpdate { SessionId = g.Slot.SessionId, Visible = visible }); }
            catch (Exception ex) { Log.Debug(ex, "ACS Drift Server: could not send ghost visibility to {Name}", client.Name); }
        }
    }

    // ------------------------------------------------------------------ interpolación
    // Posición con Hermite (usa la velocidad grabada); resto lineal. Los campos discretos
    // (marcha, flags, delta de rendimiento) se toman de la muestra anterior.
    private static GhostSample Interpolate(GhostSample[] s, double t)
    {
        var lo = 0;
        var hi = s.Length - 1;
        while (lo < hi)
        {
            var mid = (lo + hi + 1) / 2;
            if (s[mid].TimeMs <= t) lo = mid;
            else hi = mid - 1;
        }

        var a = s[lo];
        if (lo + 1 >= s.Length) return a;

        var b = s[lo + 1];
        var span = (double)b.TimeMs - a.TimeMs;
        if (span <= 0) return a;

        var u = (float)Math.Clamp((t - a.TimeMs) / span, 0, 1);
        var dt = (float)(span / 1000.0);
        var m0 = a.Velocity * dt;
        var m1 = b.Velocity * dt;

        return new GhostSample
        {
            TimeMs = a.TimeMs,
            Position = Hermite(a.Position, m0, b.Position, m1, u),
            Velocity = Vector3.Lerp(a.Velocity, b.Velocity, u),
            Rotation = new Vector3(
                LerpAngle(a.Rotation.X, b.Rotation.X, u),
                LerpAngle(a.Rotation.Y, b.Rotation.Y, u),
                LerpAngle(a.Rotation.Z, b.Rotation.Z, u)),
            TyreFL = LerpByte(a.TyreFL, b.TyreFL, u),
            TyreFR = LerpByte(a.TyreFR, b.TyreFR, u),
            TyreRL = LerpByte(a.TyreRL, b.TyreRL, u),
            TyreRR = LerpByte(a.TyreRR, b.TyreRR, u),
            SteerAngle = LerpByte(a.SteerAngle, b.SteerAngle, u),
            WheelAngle = LerpByte(a.WheelAngle, b.WheelAngle, u),
            EngineRpm = LerpUShort(a.EngineRpm, b.EngineRpm, u),
            Gear = a.Gear,
            StatusFlag = a.StatusFlag,
            Gas = LerpByte(a.Gas, b.Gas, u),
            PerformanceDelta = a.PerformanceDelta,
            NormalizedPosition = a.NormalizedPosition + (b.NormalizedPosition - a.NormalizedPosition) * u
        };
    }

    private static Vector3 Hermite(Vector3 p0, Vector3 m0, Vector3 p1, Vector3 m1, float u)
    {
        var u2 = u * u;
        var u3 = u2 * u;
        var h00 = 2 * u3 - 3 * u2 + 1;
        var h10 = u3 - 2 * u2 + u;
        var h01 = -2 * u3 + 3 * u2;
        var h11 = u3 - u2;
        return p0 * h00 + m0 * h10 + p1 * h01 + m1 * h11;
    }

    private static float LerpAngle(float a, float b, float u)
    {
        // Camino corto: la diferencia se lleva al intervalo [-AngleWrap/2, AngleWrap/2].
        var d = b - a;
        d -= AngleWrap * MathF.Round(d / AngleWrap);
        return a + d * u;
    }

    private static byte LerpByte(byte a, byte b, float u) => (byte)Math.Round(a + (b - a) * (double)u);
    private static ushort LerpUShort(ushort a, ushort b, float u) => (ushort)Math.Round(a + (b - a) * (double)u);
}
