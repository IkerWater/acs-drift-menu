using AssettoServer.Commands;
using AssettoServer.Commands.Attributes;
using JetBrains.Annotations;
using Qmmands;

namespace MapVotePlugin;

[UsedImplicitly(ImplicitUseKindFlags.Access, ImplicitUseTargetFlags.WithMembers)]
public class MapVoteCommandModule : ACModuleBase
{
    private readonly MapVotePlugin _plugin;

    public MapVoteCommandModule(MapVotePlugin plugin)
    {
        _plugin = plugin;
    }

    [Command("mapstart", "mapvote"), RequireConnectedPlayer]
    public void Start(int id) => _plugin.StartVote(Client!, id);

    [Command("mapyes", "mapsi"), RequireConnectedPlayer]
    public void Yes() => _plugin.CastVote(Client!, true);

    [Command("mapno"), RequireConnectedPlayer]
    public void No() => _plugin.CastVote(Client!, false);

    [Command("maplist"), RequireConnectedPlayer]
    public void List(int page = 1) => _plugin.SendList(Client!, page);

    [Command("mapstatus"), RequireConnectedPlayer]
    public void Status() => _plugin.SendStatus(Client!);

    [Command("mapcancel"), RequireAdmin]
    public void Cancel() => _plugin.Cancel(Client!);

    [Command("mapreload"), RequireAdmin]
    public void Reload() => _plugin.Reload(Client!);

    [Command("mapset"), RequireAdmin]
    public void Set(int id) => _plugin.AdminSet(Client!, id);
}
