using System.Numerics;
using System.Text.Json;
using Serilog;

namespace AcsDriftServerPlugin;

/// <summary>
/// Muestra de una pasada. En disco ocupa 60 bytes (ver ghost-ia-replay-diseno.md §4.2).
/// </summary>
public struct GhostSample
{
    public uint TimeMs;
    public Vector3 Position;
    public Vector3 Rotation;
    public Vector3 Velocity;
    public byte TyreFL;
    public byte TyreFR;
    public byte TyreRL;
    public byte TyreRR;
    public byte SteerAngle;
    public byte WheelAngle;
    public ushort EngineRpm;
    public byte Gear;
    public uint StatusFlag;
    public byte Gas;
    public short PerformanceDelta;
    public float NormalizedPosition;
}

/// <summary>Metadatos de una pasada (archivo &lt;id&gt;.json).</summary>
public class GhostMeta
{
    public int Id { get; set; }
    public string Name { get; set; } = "";
    public string Car { get; set; } = "";
    public string Skin { get; set; } = "";
    public string Author { get; set; } = "";
    public ulong AuthorGuid { get; set; }
    public int DurationMs { get; set; }
    public int Samples { get; set; }
    public DateTime Created { get; set; }
    public int FormatVersion { get; set; } = GhostFile.Version;
}

/// <summary>
/// Lectura y escritura de pasadas en cfg/ghosts/&lt;circuito&gt;/&lt;layout&gt;/.
/// Por pasada hay dos archivos con el mismo id: &lt;id&gt;.json (metadatos) y &lt;id&gt;.ghost (muestras).
/// </summary>
public static class GhostFile
{
    public const byte Version = 1;
    public const int SampleSize = 60;

    private static readonly byte[] Magic = "ACSG"u8.ToArray();
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };

    public static string Folder(string root, string track, string layout)
        => Path.Join(root, Clean(track), Clean(string.IsNullOrEmpty(layout) ? "default" : layout));

    public static List<GhostMeta> List(string folder)
    {
        var list = new List<GhostMeta>();
        if (!Directory.Exists(folder)) return list;

        foreach (var file in Directory.GetFiles(folder, "*.json"))
        {
            try
            {
                var meta = JsonSerializer.Deserialize<GhostMeta>(File.ReadAllText(file));
                if (meta != null && meta.Id > 0 && File.Exists(Path.ChangeExtension(file, ".ghost")))
                    list.Add(meta);
            }
            catch (Exception ex)
            {
                Log.Debug(ex, "ACS Drift Server: could not read ghost metadata {Path}", file);
            }
        }

        return list.OrderBy(m => m.Id).ToList();
    }

    /// <summary>Guarda una pasada con el siguiente id libre del circuito.</summary>
    public static GhostMeta Save(string folder, GhostMeta meta, GhostSample[] samples)
    {
        Directory.CreateDirectory(folder);

        // Id = mayor id que exista ya como .ghost, para no pisar nada aunque falte un .json.
        var maxId = 0;
        foreach (var file in Directory.GetFiles(folder, "*.ghost"))
            if (int.TryParse(Path.GetFileNameWithoutExtension(file), out var n) && n > maxId) maxId = n;

        meta.Id = maxId + 1;
        meta.Samples = samples.Length;
        meta.FormatVersion = Version;

        WriteSamples(Path.Join(folder, $"{meta.Id}.ghost"), samples);
        WriteAtomic(Path.Join(folder, $"{meta.Id}.json"), JsonSerializer.Serialize(meta, JsonOptions));
        return meta;
    }

    public static (GhostMeta Meta, GhostSample[] Samples)? Load(string folder, int id)
    {
        var json = Path.Join(folder, $"{id}.json");
        var ghost = Path.Join(folder, $"{id}.ghost");
        if (!File.Exists(json) || !File.Exists(ghost)) return null;

        var meta = JsonSerializer.Deserialize<GhostMeta>(File.ReadAllText(json));
        if (meta == null) return null;
        return (meta, ReadSamples(ghost));
    }

    public static bool Delete(string folder, int id)
    {
        var json = Path.Join(folder, $"{id}.json");
        var ghost = Path.Join(folder, $"{id}.ghost");
        if (!File.Exists(json) && !File.Exists(ghost)) return false;

        if (File.Exists(ghost)) File.Delete(ghost);
        if (File.Exists(json)) File.Delete(json);
        return true;
    }

    private static void WriteSamples(string path, GhostSample[] samples)
    {
        var tmp = path + ".tmp";
        using (var fs = File.Create(tmp))
        using (var w = new BinaryWriter(fs))
        {
            w.Write(Magic);
            w.Write(Version);
            w.Write((uint)samples.Length);
            foreach (var s in samples)
            {
                w.Write(s.TimeMs);
                WriteVector(w, s.Position);
                WriteVector(w, s.Rotation);
                WriteVector(w, s.Velocity);
                w.Write(s.TyreFL);
                w.Write(s.TyreFR);
                w.Write(s.TyreRL);
                w.Write(s.TyreRR);
                w.Write(s.SteerAngle);
                w.Write(s.WheelAngle);
                w.Write(s.EngineRpm);
                w.Write(s.Gear);
                w.Write(s.StatusFlag);
                w.Write(s.Gas);
                w.Write(s.PerformanceDelta);
                w.Write(s.NormalizedPosition);
            }
        }
        File.Move(tmp, path, true);
    }

    private static GhostSample[] ReadSamples(string path)
    {
        using var fs = File.OpenRead(path);
        using var r = new BinaryReader(fs);

        if (!r.ReadBytes(Magic.Length).SequenceEqual(Magic))
            throw new InvalidDataException($"{path}: no es una pasada de ACS Drift");
        var version = r.ReadByte();
        if (version != Version)
            throw new InvalidDataException($"{path}: versión de formato {version} no soportada");

        var count = r.ReadUInt32();
        var samples = new GhostSample[count];
        for (var i = 0; i < count; i++)
        {
            samples[i] = new GhostSample
            {
                TimeMs = r.ReadUInt32(),
                Position = ReadVector(r),
                Rotation = ReadVector(r),
                Velocity = ReadVector(r),
                TyreFL = r.ReadByte(),
                TyreFR = r.ReadByte(),
                TyreRL = r.ReadByte(),
                TyreRR = r.ReadByte(),
                SteerAngle = r.ReadByte(),
                WheelAngle = r.ReadByte(),
                EngineRpm = r.ReadUInt16(),
                Gear = r.ReadByte(),
                StatusFlag = r.ReadUInt32(),
                Gas = r.ReadByte(),
                PerformanceDelta = r.ReadInt16(),
                NormalizedPosition = r.ReadSingle()
            };
        }
        return samples;
    }

    private static void WriteVector(BinaryWriter w, Vector3 v)
    {
        w.Write(v.X);
        w.Write(v.Y);
        w.Write(v.Z);
    }

    private static Vector3 ReadVector(BinaryReader r) => new(r.ReadSingle(), r.ReadSingle(), r.ReadSingle());

    private static void WriteAtomic(string path, string text)
    {
        var tmp = path + ".tmp";
        File.WriteAllText(tmp, text);
        File.Move(tmp, path, true);
    }

    private static string Clean(string s)
    {
        foreach (var c in Path.GetInvalidFileNameChars()) s = s.Replace(c, '_');
        return s;
    }
}
