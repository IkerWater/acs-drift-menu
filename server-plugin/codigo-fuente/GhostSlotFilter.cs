using AssettoServer.Server;
using AssettoServer.Server.OpenSlotFilters;

namespace AcsDriftServerPlugin;

/// <summary>
/// Impide que un jugador entre en la plaza que ocupa el fantasma. Si no hay fantasma, deja pasar
/// al siguiente filtro de la cadena.
/// </summary>
public class GhostSlotFilter : OpenSlotFilterBase
{
    private readonly GhostService _ghosts;

    public GhostSlotFilter(GhostService ghosts)
    {
        _ghosts = ghosts;
    }

    public override async ValueTask<bool> IsSlotOpen(EntryCar entryCar, ulong guid)
    {
        if (_ghosts.IsGhostSlot(entryCar.SessionId)) return false;
        return await base.IsSlotOpen(entryCar, guid);
    }
}
