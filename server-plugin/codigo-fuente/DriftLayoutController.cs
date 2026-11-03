using System.Reflection;
using Microsoft.AspNetCore.Mvc;

namespace AcsDriftServerPlugin;

/// <summary>Lista y sirve archivos Lua de DriftZonesEditor agrupados por circuito.</summary>
[ApiController]
[Route("layouts")]
public class DriftLayoutController : ControllerBase
{
    private const long MaxLayoutSize = 5 * 1024 * 1024;
    private readonly string _layoutsRoot;

    public DriftLayoutController()
    {
        var pluginFolder = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location)
            ?? AppContext.BaseDirectory;
        _layoutsRoot = Path.GetFullPath(Path.Combine(pluginFolder, "layouts"));
    }

    [HttpGet("{track}")]
    public IActionResult List(string track)
    {
        if (!IsSafeSegment(track)) return BadRequest();

        Directory.CreateDirectory(_layoutsRoot);
        var trackFolder = GetTrackFolder(track);
        if (trackFolder == null || !Directory.Exists(trackFolder))
            return Ok(new { track, layouts = Array.Empty<object>() });
        if ((System.IO.File.GetAttributes(trackFolder) & FileAttributes.ReparsePoint) != 0)
            return Ok(new { track, layouts = Array.Empty<object>() });

        var layouts = Directory.EnumerateFiles(trackFolder)
            .Where(path => string.Equals(Path.GetExtension(path), ".lua", StringComparison.OrdinalIgnoreCase))
            .Where(path => (System.IO.File.GetAttributes(path) & FileAttributes.ReparsePoint) == 0)
            .Select(path => new FileInfo(path))
            .Where(file => file.Length <= MaxLayoutSize)
            .OrderBy(file => file.Name, StringComparer.OrdinalIgnoreCase)
            .Select(file => new { name = file.Name, size = file.Length })
            .ToArray();

        return Ok(new { track, layouts });
    }

    [HttpGet("{track}/{fileName}")]
    public IActionResult Download(string track, string fileName)
    {
        if (!IsSafeSegment(track) || !IsSafeSegment(fileName)
            || !string.Equals(Path.GetExtension(fileName), ".lua", StringComparison.OrdinalIgnoreCase))
            return BadRequest();

        var trackFolder = GetTrackFolder(track);
        if (trackFolder == null || !Directory.Exists(trackFolder)
            || (System.IO.File.GetAttributes(trackFolder) & FileAttributes.ReparsePoint) != 0)
            return NotFound();

        var path = Path.GetFullPath(Path.Combine(trackFolder, fileName));
        if (!path.StartsWith(trackFolder + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
            return BadRequest();
        if (!System.IO.File.Exists(path)
            || (System.IO.File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
            return NotFound();
        if (new FileInfo(path).Length > MaxLayoutSize) return StatusCode(413);

        return PhysicalFile(path, "application/octet-stream", fileName);
    }

    private string? GetTrackFolder(string track)
    {
        var path = Path.GetFullPath(Path.Combine(_layoutsRoot, track));
        return path.StartsWith(_layoutsRoot + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)
            ? path
            : null;
    }

    private static bool IsSafeSegment(string value)
    {
        return !string.IsNullOrWhiteSpace(value)
            && value != "."
            && value != ".."
            && !value.Contains('/')
            && !value.Contains('\\')
            && value.IndexOfAny(Path.GetInvalidFileNameChars()) < 0;
    }
}
