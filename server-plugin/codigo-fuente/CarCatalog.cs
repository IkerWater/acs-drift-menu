using System.Text.Json;
using System.Text.RegularExpressions;
using AssettoServer.Server;
using Serilog;

namespace AcsDriftServerPlugin;

public record CarEntry(string Id, string Name, int Free, int Total);

/// <summary>
/// Agrupa las plazas del entry list del servidor por modelo de coche (carpeta) y calcula,
/// en cada consulta, cuantas estan libres (sin cliente conectado). No hace falta mantener
/// una lista a mano: el entry list del servidor (presets) es la unica fuente de verdad.
/// </summary>
public class CarCatalog
{
    private const string CarsFolder = "content/cars";

    private readonly EntryCarManager _entryCarManager;
    private readonly Dictionary<string, string> _nameCache = new(StringComparer.OrdinalIgnoreCase);

    public CarCatalog(EntryCarManager entryCarManager)
    {
        _entryCarManager = entryCarManager;
    }

    public IReadOnlyList<CarEntry> List()
    {
        var counts = new Dictionary<string, (int Free, int Total)>(StringComparer.OrdinalIgnoreCase);

        // [VERIFICAR] EntryCarManager.EntryCars: todas las plazas del entry list (una por [CAR_n]).
        // EntryCar.Model = carpeta del coche (content/cars/<model>); EntryCar.Client = cliente
        // conectado en esa plaza (null si esta libre); EntryCar.AiControlled = plaza ocupada por
        // trafico IA (AI=fixed/auto), no cuenta como libre para un jugador.
        foreach (var car in _entryCarManager.EntryCars)
        {
            if (string.IsNullOrEmpty(car.Model)) continue;

            counts.TryGetValue(car.Model, out var c);
            var free = car.Client == null && !car.AiControlled ? 1 : 0;
            counts[car.Model] = (c.Free + free, c.Total + 1);
        }

        return counts
            .Select(kv => new CarEntry(kv.Key, DisplayName(kv.Key), kv.Value.Free, kv.Value.Total))
            .OrderByDescending(c => c.Free > 0)
            .ThenBy(c => c.Name, StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    private string DisplayName(string model)
    {
        if (_nameCache.TryGetValue(model, out var cached)) return cached;

        var name = ReadName(Path.Combine(CarsFolder, model, "ui", "ui_car.json")) ?? model;
        _nameCache[model] = name;
        return name;
    }

    // Mismo lector tolerante que TrackCatalog.ReadName: muchos ui_car.json de AC no son JSON estricto.
    private static string? ReadName(string path)
    {
        try
        {
            if (!File.Exists(path)) return null;
            var text = File.ReadAllText(path);

            try
            {
                using var doc = JsonDocument.Parse(text, new JsonDocumentOptions
                {
                    AllowTrailingCommas = true,
                    CommentHandling = JsonCommentHandling.Skip
                });
                if (doc.RootElement.ValueKind == JsonValueKind.Object &&
                    doc.RootElement.TryGetProperty("name", out var n) &&
                    n.ValueKind == JsonValueKind.String)
                    return Clean(n.GetString());
            }
            catch (JsonException)
            {
                var m = Regex.Match(text, "\"name\"\\s*:\\s*\"([^\"]*)\"");
                if (m.Success) return Clean(m.Groups[1].Value);
            }
        }
        catch (Exception ex)
        {
            Log.Debug(ex, "ACS Drift Server: no se pudo leer {Path}", path);
        }

        return null;
    }

    private static string? Clean(string? s)
    {
        if (string.IsNullOrWhiteSpace(s)) return null;
        return Regex.Replace(s.Trim(), "\\s+", " ");
    }
}
