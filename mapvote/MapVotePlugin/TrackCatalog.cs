using System.Text.Json;
using System.Text.RegularExpressions;
using Serilog;

namespace MapVotePlugin;

public record TrackEntry(int Id, string Track, string Layout, string Name);

/// <summary>
/// Escanea content/tracks y construye la lista de mapas + layouts instalados.
/// Layout "" = layout por defecto (CONFIG_TRACK vacio en server_cfg.ini).
/// </summary>
public class TrackCatalog
{
    private static readonly HashSet<string> NonLayoutDirs = new(StringComparer.OrdinalIgnoreCase)
    {
        "ui", "data", "skins", "ai", "extension", "texture", "textures", "sfx", "models", "lods"
    };

    private readonly MapVoteConfiguration _config;
    private volatile IReadOnlyList<TrackEntry> _entries = Array.Empty<TrackEntry>();

    public IReadOnlyList<TrackEntry> Entries => _entries;

    public TrackCatalog(MapVoteConfiguration config)
    {
        _config = config;
        Reload();
    }

    public bool TryGet(int id, out TrackEntry entry)
    {
        var list = _entries;
        if (id >= 0 && id < list.Count)
        {
            entry = list[id];
            return true;
        }

        entry = null!;
        return false;
    }

    public TrackEntry? Find(string track, string layout)
    {
        return _entries.FirstOrDefault(e =>
            string.Equals(e.Track, track, StringComparison.OrdinalIgnoreCase) &&
            string.Equals(e.Layout, layout ?? "", StringComparison.OrdinalIgnoreCase));
    }

    public void Reload()
    {
        var found = new List<(string Track, string Layout, string Name)>();
        var root = _config.TracksFolder;

        if (!Directory.Exists(root))
        {
            Log.Warning("MapVote: la carpeta de circuitos no existe: {Root}", Path.GetFullPath(root));
            _entries = Array.Empty<TrackEntry>();
            return;
        }

        foreach (var trackDir in Directory.GetDirectories(root))
        {
            var trackId = Path.GetFileName(trackDir);
            if (_config.ExcludeTracks.Contains(trackId, StringComparer.OrdinalIgnoreCase)) continue;

            var uiDir = Path.Combine(trackDir, "ui");
            var layouts = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            // Layout por defecto
            if (Directory.Exists(Path.Combine(trackDir, "data")) || File.Exists(Path.Combine(uiDir, "ui_track.json")))
                layouts.Add("");

            // Layouts con datos propios: <track>/<layout>/data
            foreach (var d in Directory.GetDirectories(trackDir))
            {
                var name = Path.GetFileName(d);
                if (NonLayoutDirs.Contains(name)) continue;
                if (Directory.Exists(Path.Combine(d, "data"))) layouts.Add(name);
            }

            // Layouts con ficha de UI: <track>/ui/<layout>/ui_track.json
            if (Directory.Exists(uiDir))
            {
                foreach (var d in Directory.GetDirectories(uiDir))
                {
                    if (File.Exists(Path.Combine(d, "ui_track.json"))) layouts.Add(Path.GetFileName(d));
                }
            }

            if (layouts.Count == 0) continue;

            var trackName = ReadName(Path.Combine(uiDir, "ui_track.json")) ?? trackId;

            foreach (var layout in layouts)
            {
                string display;
                if (layout.Length == 0)
                {
                    display = trackName;
                }
                else
                {
                    var layoutName = ReadName(Path.Combine(uiDir, layout, "ui_track.json"));
                    if (layoutName == null)
                        display = $"{trackName} [{layout}]";
                    else if (layoutName.Contains(trackName, StringComparison.OrdinalIgnoreCase))
                        display = layoutName;
                    else
                        display = $"{trackName} - {layoutName}";
                }

                found.Add((trackId, layout, display));
            }
        }

        var sorted = found
            .OrderBy(f => f.Name, StringComparer.OrdinalIgnoreCase)
            .ThenBy(f => f.Layout, StringComparer.OrdinalIgnoreCase)
            .Select((f, i) => new TrackEntry(i, f.Track, f.Layout, f.Name))
            .ToList();

        _entries = sorted;
        Log.Information("MapVote: {Count} mapas/layouts encontrados en {Root}", sorted.Count, root);
    }

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
                // Muchos ui_track.json de AC no son JSON estricto: probamos con regex.
                var m = Regex.Match(text, "\"name\"\\s*:\\s*\"([^\"]*)\"");
                if (m.Success) return Clean(m.Groups[1].Value);
            }
        }
        catch (Exception ex)
        {
            Log.Debug(ex, "MapVote: no se pudo leer {Path}", path);
        }

        return null;
    }

    private static string? Clean(string? s)
    {
        if (string.IsNullOrWhiteSpace(s)) return null;
        return Regex.Replace(s.Trim(), "\\s+", " ");
    }
}
