using Microsoft.AspNetCore.Mvc;

namespace AcsDriftServerPlugin;

/// <summary>API de solo lectura para mostrar los presets configurados en el menú admin.</summary>
[ApiController]
[Route("admin")]
public class AdminPresetController : ControllerBase
{
    private readonly PresetCatalog _catalog;

    public AdminPresetController(PresetCatalog catalog)
    {
        _catalog = catalog;
    }

    [HttpGet("presets")]
    public IActionResult Presets()
        => Ok(new
        {
            presets = _catalog.Entries.Select(preset => new
            {
                id = preset.Id,
                name = preset.Name,
                current = preset.IsCurrent
            })
        });
}
