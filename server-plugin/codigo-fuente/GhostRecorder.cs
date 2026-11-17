using AssettoServer.Server;
using AssettoServer.Shared.Network.Packets.Incoming;

namespace AcsDriftServerPlugin;

/// <summary>
/// Graba las posiciones que el servidor recibe de un coche (EntryCar.PositionUpdateReceived).
/// Se usa desde el hilo de red: todo el acceso a la lista va bajo _lock.
/// </summary>
public sealed class GhostRecorder
{
    private readonly object _lock = new();
    private readonly List<GhostSample> _samples = new();
    private readonly uint _maxMs;
    private bool _hasBase;
    private uint _baseTs;
    private uint _lastTs;
    private bool _full;

    public GhostRecorder(EntryCar car, int maxSeconds)
    {
        Car = car;
        _maxMs = (uint)maxSeconds * 1000u;
        car.PositionUpdateReceived += OnPositionUpdate;
    }

    public EntryCar Car { get; }

    /// <summary>True cuando se ha alcanzado la duración máxima.</summary>
    public bool Full
    {
        get { lock (_lock) return _full; }
    }

    public int ElapsedMs
    {
        get { lock (_lock) return _samples.Count == 0 ? 0 : (int)_samples[^1].TimeMs; }
    }

    private void OnPositionUpdate(EntryCar sender, in PositionUpdateIn update)
    {
        lock (_lock)
        {
            if (_full) return;

            // Tiempo relativo al primer paquete, con el reloj del cliente (LastRemoteTimestamp):
            // así el jitter de red no deforma la pasada.
            var ts = update.LastRemoteTimestamp;
            if (!_hasBase)
            {
                _hasBase = true;
                _baseTs = ts;
            }
            if (_samples.Count > 0 && ts == _lastTs) return;

            var ms = unchecked(ts - _baseTs);
            if (ms > _maxMs)
            {
                _full = true;
                return;
            }

            _lastTs = ts;
            _samples.Add(new GhostSample
            {
                TimeMs = ms,
                Position = update.Position,
                Rotation = update.Rotation,
                Velocity = update.Velocity,
                TyreFL = update.TyreAngularSpeedFL,
                TyreFR = update.TyreAngularSpeedFR,
                TyreRL = update.TyreAngularSpeedRL,
                TyreRR = update.TyreAngularSpeedRR,
                SteerAngle = update.SteerAngle,
                WheelAngle = update.WheelAngle,
                EngineRpm = update.EngineRpm,
                Gear = update.Gear,
                StatusFlag = (uint)update.StatusFlag,
                Gas = update.Gas,
                PerformanceDelta = update.PerformanceDelta,
                NormalizedPosition = update.NormalizedPosition
            });
        }
    }

    /// <summary>Deja de grabar y devuelve las muestras recogidas.</summary>
    public GhostSample[] Stop()
    {
        Car.PositionUpdateReceived -= OnPositionUpdate;
        lock (_lock) return _samples.ToArray();
    }
}
