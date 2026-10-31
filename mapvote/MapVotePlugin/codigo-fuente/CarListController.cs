using Microsoft.AspNetCore.Mvc;

namespace MapVotePlugin;

/// <summary>API HTTP que consulta el menu del juego (lua/tabs/car.lua) para saber que coches
/// del entry list tienen plazas libres ahora mismo.</summary>
[ApiController]
[Route("cars")]
public class CarListController : ControllerBase
{
    private readonly CarCatalog _catalog;

    public CarListController(CarCatalog catalog)
    {
        _catalog = catalog;
    }

    [HttpGet("list")]
    public IActionResult List()
        => Ok(_catalog.List().Select(c => new { id = c.Id, name = c.Name, free = c.Free, total = c.Total }));
}
