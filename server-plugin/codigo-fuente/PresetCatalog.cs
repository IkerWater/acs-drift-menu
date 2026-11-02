using AssettoServer.Server.Configuration;
using Serilog;

namespace AcsDriftServerPlugin;

public record PresetEntry(int Id, string Name, bool IsCurrent);

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
            Log.Warning("ACS Drift Server: no se encuentra la carpeta de presets: {Path}",
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
                string.Equals(name, currentPreset, StringComparison.OrdinalIgnoreCase)))
            .ToArray();

        Log.Information("ACS Drift Server: {Count} presets encontrados en {Path}",
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

    private static string? GetPresetName(string? preset)
    {
        if (string.IsNullOrWhiteSpace(preset)) return null;
        return Path.GetFileName(preset.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar));
    }
}
