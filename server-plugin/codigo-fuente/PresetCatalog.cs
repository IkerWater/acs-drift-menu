using AssettoServer.Server.Configuration;
using Serilog;

namespace AcsDriftServerPlugin;

/// <summary>Folder = carpeta en presets/ (lo que se pasa a AssettoServer); Name = nombre para mostrar.</summary>
public record PresetEntry(int Id, string Folder, string Name, bool IsCurrent);

/// <summary>Lista los presets disponibles en la carpeta presets/ del servidor.</summary>
public class PresetCatalog
{
    private readonly IReadOnlyList<PresetEntry> _entries;

    public IReadOnlyList<PresetEntry> Entries => _entries;

    public PresetCatalog(ACServerConfiguration serverConfig)
    {
        var currentPreset = GetPresetName(serverConfig.Preset);
        const string presetsFolder = "presets";
        if (!Directory.Exists(presetsFolder))
        {
            Log.Warning("ACS Drift Server: preset folder not found: {Path}",
                Path.GetFullPath(presetsFolder));
            _entries = Array.Empty<PresetEntry>();
            return;
        }

        _entries = Directory.GetDirectories(presetsFolder)
            .Where(directory => File.Exists(Path.Combine(directory, "server_cfg.ini")))
            .Select(directory => new DirectoryInfo(directory).Name)
            .OrderBy(name => name, StringComparer.OrdinalIgnoreCase)
            .Select((name, id) => new PresetEntry(
                id,
                name,
                DisplayName(presetsFolder, name),
                string.Equals(name, currentPreset, StringComparison.OrdinalIgnoreCase)))
            .ToArray();

        Log.Information("ACS Drift Server: found {Count} presets in {Path}",
            _entries.Count, Path.GetFullPath(presetsFolder));
    }

    public bool TryGet(int id, out PresetEntry entry)
    {
        if (id >= 0 && id < _entries.Count)
        {
            entry = _entries[id];
            return true;
        }

        entry = null!;
        return false;
    }

    // Nombre que se ve en AC Panel (Meta.Name de plugin_voting_preset_cfg.yml); si no hay, el de la carpeta.
    private static string DisplayName(string presetsFolder, string folder)
    {
        try
        {
            var path = Path.Combine(presetsFolder, folder, "plugin_voting_preset_cfg.yml");
            if (File.Exists(path))
            {
                var inMeta = false;
                foreach (var raw in File.ReadLines(path))
                {
                    if (raw.Length > 0 && !char.IsWhiteSpace(raw[0])) inMeta = raw.TrimEnd() == "Meta:";
                    else if (inMeta && raw.TrimStart().StartsWith("Name:", StringComparison.Ordinal))
                    {
                        var v = raw.TrimStart()[5..].Trim().Trim('"', '\'');
                        if (v.Length > 0) return v.Replace("\\\"", "\"");
                    }
                }
            }
        }
        catch (Exception ex)
        {
            Log.Debug(ex, "ACS Drift Server: could not read preset name for {Folder}", folder);
        }
        return folder;
    }

    private static string? GetPresetName(string? preset)
    {
        if (string.IsNullOrWhiteSpace(preset)) return null;
        return Path.GetFileName(preset.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar));
    }
}
