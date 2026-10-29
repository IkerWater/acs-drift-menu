using Microsoft.AspNetCore.Mvc;

namespace MapVotePlugin;

/// <summary>API HTTP que consulta el menu (script Lua) desde el cliente.</summary>
[ApiController]
[Route("mapvote")]
public class MapVoteController : ControllerBase
{
    private readonly MapVotePlugin _plugin;
    private readonly TrackCatalog _catalog;

    public MapVoteController(MapVotePlugin plugin, TrackCatalog catalog)
    {
        _plugin = plugin;
        _catalog = catalog;
    }

    [HttpGet("tracks")]
    public IActionResult Tracks()
        => Ok(_catalog.Entries.Select(e => new { id = e.Id, track = e.Track, layout = e.Layout, name = e.Name }));

    [HttpGet("status")]
    public IActionResult Status() => Ok(_plugin.GetStatus());
}
