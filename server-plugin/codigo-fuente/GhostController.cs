using Microsoft.AspNetCore.Mvc;

namespace AcsDriftServerPlugin;

/// <summary>API HTTP de los fantasmas para el menú del juego (solo lectura; las acciones van por evento online).</summary>
[ApiController]
[Route("ghost")]
public class GhostController : ControllerBase
{
    private readonly GhostService _ghosts;

    public GhostController(GhostService ghosts)
    {
        _ghosts = ghosts;
    }

    [HttpGet("list")]
    public IActionResult List()
    {
        var active = _ghosts.ActiveId;
        return Ok(_ghosts.ListSaved().Select(g => new
        {
            id = g.Id,
            name = g.Name,
            car = g.Car,
            author = g.Author,
            durationMs = g.DurationMs,
            created = g.Created,
            active = g.Id == active
        }));
    }

    [HttpGet("status")]
    public IActionResult Status() => Ok(_ghosts.GetStatus());

#if MAPVOTE_TEST
    [HttpPost("test/make")]
    public IActionResult TestMake() => Ok(_ghosts.TestMakeAndLoad());
#endif
}
