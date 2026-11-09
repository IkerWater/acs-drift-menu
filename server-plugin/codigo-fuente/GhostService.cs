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
        // Vuelta completa de los ángulos de esta pasada: 2π si vienen en radianes, 360 si en grados
        public float AngleWrap { get; init; } = MathF.Tau;
        // null = todavía no se ha enviado la visibilidad a los clientes
        public bool? Visible { get; set; }
    }

    private const string Tag = "[Ghost]";
    // No está confirmado si PositionUpdateIn.Rotation viene en radianes o en grados: se deduce de cada pasada
    // (WrapFor). El colega verificó en una pasada real que son radianes (máx. |rot| = 3.134 ≈ π). Con la vuelta equivocada, al cruzar ±π el coche daría una vuelta entera de golpe.
    internal static float WrapFor(GhostSample[] samples)
    {
        var max = 0f;
        foreach (var x in samples)
            max = MathF.Max(max, MathF.Max(MathF.Abs(x.Rotation.X), MathF.Max(MathF.Abs(x.Rotation.Y), MathF.Abs(x.Rotation.Z))));
        return max <= 7f ? MathF.Tau : 360f;
    }
    // Profundidad a la que se manda el fantasma mientras está oculto (queda fuera del circuito).
    private const float HideDepth = 1000f;
    // Cuántos paquetes de posición se mandan antes de mostrarlo, para que no aparezca "deslizándose".
    private const int SpawnRepeats = 3;
    private const int MinSamples = 10;
    // Por debajo de esta velocidad (m/s) el coche cuenta como parado al recortar el principio.
    private const float MoveSpeed = 0.5f;
    // Parada artificial al principio de cada pasada, para dar tiempo a reaccionar a su salida.
    private const uint LeadInMs = 1000;
    private const uint LeadInStepMs = 50;
    // Tiempo que se espera la confirmación de una grabación antes de descartarla.
    private const long PendingTimeoutMs = 5 * 60 * 1000;

    // Estados que recibe el menú (ACP_GhostState.state)
    private const byte StateIdle = 0;
    private const byte StateRecording = 1;
    private const byte StateSaved = 2;
    private const byte StateError = 3;
    private const byte StatePending = 4; // grabada, esperando a que se guarde o se descarte

    // Códigos de error (ACP_GhostState.code)
    private const byte ErrNotAdmin = 1;
    private const byte ErrNoCar = 2;
    private const byte ErrAlreadyRecording = 3;
    private const byte ErrTooShort = 4;
    private const byte ErrNoSlot = 5;
    private const byte ErrNotFound = 6;
    private const byte ErrNotRecording = 7;
    private const byte ErrNoPending = 8;

    /// <summary>Grabación terminada que espera confirmación. No se escribe en disco hasta guardarla.</summary>
    private sealed class PendingGhost
    {
        public required GhostMeta Meta { get; init; }
        public required GhostSample[] Samples { get; init; }
        public ACTcpClient? Owner { get; init; }
        public required long CreatedTick { get; init; }
    }

    private readonly MapVoteConfiguration _config;
    private readonly ACServerConfiguration _serverConfig;
    private readonly EntryCarManager _entryCarManager;
    private readonly SessionManager _sessionManager;

    private readonly object _lock = new();
    private GhostRecorder? _recorder;
    private string _recAuthor = "";
    private ulong _recAuthorGuid;
    private string _recCar = "";
    private string _recSkin = "";
    private PendingGhost? _pending;
    private ActiveGhost? _active;
    private readonly HashSet<ACTcpClient> _announced = new();
    private byte _pakSequence;

    public GhostService(MapVoteConfiguration config,
        ACServerConfiguration serverConfig,
        EntryCarManager entryCarManager,
        SessionManager sessionManager,
        CSPClientMessageTypeManager clientMessageTypeManager)
    {
        _config = config;
        _serverConfig = serverConfig;
        _entryCarManager = entryCarManager;
        _sessionManager = sessionManager;

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
            case 7: SavePending(client); break;
            case 8: DiscardPending(client); break;
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

            if (_pending != null)
            {
                DiscardPendingLocked(client);
                Send(client, "The previous unsaved recording was discarded.");
            }

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
            if (_recorder == null)
            {
                // Sin grabación en marcha, cancelar descarta la que espera confirmación.
                if (_pending != null) { DiscardPendingLocked(client); Send(client, "Ghost recording discarded."); return; }
                Fail(client, ErrNotRecording, "There is no ghost recording in progress.");
                return;
            }
            _recorder.Stop();
            _recorder = null;
            SendState(client, StateIdle, 0, 0, 0);
            Send(client, "Ghost recording cancelled.");
        }
    }

    // con _lock tomado. Para la grabación y la deja pendiente de confirmar (no se guarda todavía).
    // notify = quien grabó y tiene que confirmarla.
    private void FinishRecordingLocked(ACTcpClient? notify)
    {
        var recorder = _recorder!;
        _recorder = null;
        var raw = recorder.Stop();

        // Hace falta al menos 1 s en movimiento, además de la parada inicial.
        var samples = raw.Length < MinSamples ? null : TrimStart(raw);
        if (samples == null || samples.Length < MinSamples || samples[^1].TimeMs < LeadInMs + 1000)
        {
            if (notify != null) Fail(notify, ErrTooShort, "The recording is too short to be saved.");
            else Broadcast("Ghost recording discarded: it is too short.");
            return;
        }

        _pending = new PendingGhost
        {
            Meta = new GhostMeta
            {
                Name = $"{_recAuthor} - {_recCar}",
                Car = _recCar,
                Skin = _recSkin,
                Author = _recAuthor,
                AuthorGuid = _recAuthorGuid,
                DurationMs = (int)samples[^1].TimeMs,
                Created = DateTime.UtcNow
            },
            Samples = samples,
            Owner = notify,
            CreatedTick = Environment.TickCount64
        };

        var seconds = _pending.Meta.DurationMs / 1000;
        if (notify != null)
        {
            SendState(notify, StatePending, seconds, 0, 0);
            Send(notify, $"Ghost recorded ({seconds} s). Save it or discard it from the menu (or /ghostsave, /ghostdiscard).");
        }
        Log.Information("ACS Drift Server: ghost recorded by {Name} ({Car}, {Seconds} s, {Raw} -> {Trimmed} samples), waiting for confirmation",
            _recAuthor, _recCar, seconds, raw.Length, samples.Length);
    }

    /// <summary>
    /// Quita la parada del principio y pone en su lugar exactamente LeadInMs de coche quieto en la
    /// posición de salida. Devuelve null si el coche no llega a moverse.
    /// </summary>
    internal static GhostSample[]? TrimStart(GhostSample[] samples)
    {
        var move = Array.FindIndex(samples, s => s.Velocity.Length() > MoveSpeed);
        if (move < 0) return null;

        // Postura de la última muestra parada (no la primera: al empezar el coche puede estar aún asentándose).
        var hold = samples[Math.Max(0, move - 1)];
        hold.Velocity = Vector3.Zero;
        hold.Gas = 0;

        var result = new List<GhostSample>(samples.Length - move + (int)(LeadInMs / LeadInStepMs));
        for (uint t = 0; t < LeadInMs; t += LeadInStepMs)
        {
            var s = hold;
            s.TimeMs = t;
            result.Add(s);
        }

        var tMove = samples[move].TimeMs;
        for (var i = move; i < samples.Length; i++)
        {
            var s = samples[i];
            s.TimeMs = samples[i].TimeMs - tMove + LeadInMs;
            result.Add(s);
        }
        return result.ToArray();
    }

    internal void SavePending(ACTcpClient client)
    {
        if (!IsAdmin(client)) return;
        lock (_lock)
        {
            if (_pending == null) { Fail(client, ErrNoPending, "There is no recorded ghost waiting to be saved."); return; }
            var p = _pending;
            _pending = null;

            var saved = GhostFile.Save(CurrentFolder(), p.Meta, p.Samples);
            var seconds = saved.DurationMs / 1000;

            SendState(client, StateSaved, seconds, 0, saved.Id);
            if (p.Owner != null && p.Owner != client) SendState(p.Owner, StateIdle, 0, 0, 0);
            Broadcast($"Ghost saved: {saved.Author} · {saved.Car} · {seconds} s (id {saved.Id}).");
            Log.Information("ACS Drift Server: ghost {Id} saved ({Car}, {Seconds} s)", saved.Id, saved.Car, seconds);
        }
    }

    internal void DiscardPending(ACTcpClient client)
    {
        if (!IsAdmin(client)) return;
        lock (_lock)
        {
            if (_pending == null) { Fail(client, ErrNoPending, "There is no recorded ghost waiting to be saved."); return; }
            DiscardPendingLocked(client);
            Send(client, "Ghost recording discarded.");
        }
    }

    // con _lock tomado. Avisa a quien lo pidió y al que grabó (si siguen conectados).
    private void DiscardPendingLocked(ACTcpClient? client)
    {
        var p = _pending;
        if (p == null) return;
        _pending = null;
        if (client != null) SendState(client, StateIdle, 0, 0, 0);
        if (p.Owner != null && p.Owner != client) SendState(p.Owner, StateIdle, 0, 0, 0);
        Log.Information("ACS Drift Server: unsaved ghost recording by {Name} discarded", p.Meta.Author);
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
                StartTick = Environment.TickCount64,
                AngleWrap = WrapFor(samples)
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

#if MAPVOTE_TEST
    // Solo pruebas: crea una pasada sintética (un círculo de 20 s) con el primer modelo del entry list y la carga.
    internal object TestMakeAndLoad()
    {
        lock (_lock)
        {
            var model = _entryCarManager.EntryCars.First(c => !c.AiControlled).Model;
            var samples = new GhostSample[400];
            for (var i = 0; i < samples.Length; i++)
            {
                var a = i * 0.05f;
                samples[i] = new GhostSample { TimeMs = (uint)(i * 50), Position = new Vector3(MathF.Cos(a) * 50, 0, MathF.Sin(a) * 50),
                    Rotation = new Vector3(a * 57.3f % 360f, 0, 0), Velocity = new Vector3(-MathF.Sin(a) * 50, 0, MathF.Cos(a) * 50), EngineRpm = 5000, Gear = 3 };
            }
            var meta = GhostFile.Save(CurrentFolder(), new GhostMeta { Name = "test", Car = model, Author = "test", DurationMs = 19950, Created = DateTime.UtcNow }, samples);
            var loaded = GhostFile.Load(CurrentFolder(), meta.Id)!.Value;
            var slot = FindFreeSlot(loaded.Meta.Car);
            if (slot == null) return new { error = "sin plaza" };
            ReleaseLocked();
            _active = new ActiveGhost { Meta = loaded.Meta, Samples = loaded.Samples, Slot = slot, StartTick = Environment.TickCount64, AngleWrap = WrapFor(loaded.Samples) };
            // comprobación del ángulo: de 3.1 a -3.1 rad, a mitad de camino tiene que salir ±π, no 0
            var t2 = new[] { new GhostSample { TimeMs = 0, Rotation = new Vector3(3.1f, 0, 0) }, new GhostSample { TimeMs = 100, Rotation = new Vector3(-3.1f, 0, 0) } };
            var mid = Interpolate(t2, 50, WrapFor(t2)).Rotation.X;
            return new { id = meta.Id, slot = slot.SessionId, samples = loaded.Samples.Length, folder = CurrentFolder(), wrap = WrapFor(loaded.Samples), radMid = mid };
        }
    }
#endif

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
                pending = _pending != null,
                pendingSeconds = _pending == null ? 0 : _pending.Meta.DurationMs / 1000,
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
                FinishRecordingLocked(_recorder.Car.Client);
            }
            else if (_recorder.Car.Client == null)
            {
                // No queda nadie para confirmarla: se descarta.
                _recorder.Stop();
                _recorder = null;
                Broadcast("The player left during the ghost recording; it was discarded.");
            }
        }

        if (_pending != null)
        {
            var ownerLeft = _pending.Owner != null && !connected.Contains(_pending.Owner);
            var expired = Environment.TickCount64 - _pending.CreatedTick > PendingTimeoutMs;
            if (ownerLeft || expired)
            {
                var owner = ownerLeft ? null : _pending.Owner;
                DiscardPendingLocked(null);
                if (owner != null) Send(owner, "The unsaved ghost recording was discarded (not confirmed in time).");
                if (ownerLeft) Log.Information("ACS Drift Server: the author left before confirming the ghost recording");
            }
        }

        var g = _active;
        if (g == null || g.Meta.DurationMs <= 0) return;

        // Pasada + pausa entre vueltas; el fantasma vuelve a empezar desde el principio de la pasada.
        var cycle = g.Meta.DurationMs + _config.GhostLoopGapSeconds * 1000L;
        var elapsed = (Environment.TickCount64 - g.StartTick) % cycle;

        if (elapsed < g.Meta.DurationMs)
        {
            if (g.Visible != true) Show(g);
            SendPose(g, Interpolate(g.Samples, elapsed, g.AngleWrap));
        }
        else if (g.Visible != false)
        {
            Hide(g);
        }
    }

    // Aparecer en el punto de inicio: unos paquetes ya ahí y luego se muestra.
    private void Show(ActiveGhost g)
    {
        var first = g.Samples[0];
        for (var i = 0; i < SpawnRepeats; i++) SendPose(g, first);
        SendVisibility(g, CSPCarVisibility.Visible);
        g.Visible = true;
    }

    // Ocultarlo y mandarlo bajo el circuito para que no quede un obstáculo invisible en la pausa.
    private void Hide(ActiveGhost g)
    {
        SendVisibility(g, CSPCarVisibility.Invisible);
        var far = g.Samples[0];
        far.Position = new Vector3(far.Position.X, far.Position.Y - HideDepth, far.Position.Z);
        for (var i = 0; i < SpawnRepeats; i++) SendPose(g, far);
        g.Visible = false;
    }

    private void SendPose(ActiveGhost g, GhostSample s)
    {
        var seq = _pakSequence++;
        // Reloj del servidor de AssettoServer (cronómetro desde que arrancó el servidor), el mismo con el
        // que se calcula TimeOffset. No usar Environment.TickCount64: cuenta desde que arrancó la máquina
        // y los paquetes llegaban con días de adelanto, así que el cliente extrapolaba la posición a 1e12 m.
        var now = _sessionManager.ServerTimeMilliseconds;
        foreach (var client in _announced)
        {
            try
            {
                // Igual que la IA en EntryCar.GetPositionUpdateForCar: ServerTimeMilliseconds menos el offset del receptor.
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
    internal static GhostSample Interpolate(GhostSample[] s, double t, float wrap)
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
                LerpAngle(a.Rotation.X, b.Rotation.X, u, wrap),
                LerpAngle(a.Rotation.Y, b.Rotation.Y, u, wrap),
                LerpAngle(a.Rotation.Z, b.Rotation.Z, u, wrap)),
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

    private static float LerpAngle(float a, float b, float u, float wrap)
    {
        // Camino corto: la diferencia se lleva al intervalo [-wrap/2, wrap/2].
        var d = b - a;
        d -= wrap * MathF.Round(d / wrap);
        return a + d * u;
    }

    private static byte LerpByte(byte a, byte b, float u) => (byte)Math.Round(a + (b - a) * (double)u);
    private static ushort LerpUShort(ushort a, ushort b, float u) => (ushort)Math.Round(a + (b - a) * (double)u);
}
