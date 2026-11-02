using AssettoServer.Commands;
using AssettoServer.Commands.Attributes;
using JetBrains.Annotations;
using Qmmands;
using Serilog;

namespace AcsDriftServerPlugin;

[UsedImplicitly(ImplicitUseKindFlags.Access, ImplicitUseTargetFlags.WithMembers)]
public class MapVoteCommandModule : ACModuleBase
{
    private readonly AcsDriftServerPlugin _plugin;

    public MapVoteCommandModule(AcsDriftServerPlugin plugin)
    {
        _plugin = plugin;
    }

    // Log the full error and send a short summary to the player instead of AssettoServer's generic message.
    private void Run(string what, Action action)
    {
        try { action(); }
        catch (Exception ex)
        {
            var e = ex;
            var chain = new List<string>();
            while (e != null) { chain.Add($"{e.GetType().FullName}: {e.Message}"); e = e.InnerException; }
            string trace;
            try { trace = ex.StackTrace ?? ""; } catch (Exception t) { trace = "(sin traza: " + t.Message + ")"; }
            Log.Error("ACS Drift Server: failure in {What}: {Chain}\n{Trace}", what, string.Join(" -> ", chain), trace);
            try { Client?.SendChatMessage($"[Map] Error: {ex.Message}"); } catch { /* nothing */ }
        }
    }

    [Command("mapstart", "mapvote"), RequireConnectedPlayer]
    public void Start(int id) => Run("StartVote", () => _plugin.StartVote(Client!, id));

    [Command("mapyes", "mapsi"), RequireConnectedPlayer]
    public void Yes() => Run("CastVote", () => _plugin.CastVote(Client!, true));

    [Command("mapno"), RequireConnectedPlayer]
    public void No() => Run("CastVote", () => _plugin.CastVote(Client!, false));

    [Command("maplist"), RequireConnectedPlayer]
    public void List(int page = 1) => Run("SendList", () => _plugin.SendList(Client!, page));

    [Command("mapstatus"), RequireConnectedPlayer]
    public void Status() => Run("SendStatus", () => _plugin.SendStatus(Client!));

    [Command("mapcancel"), RequireAdmin]
    public void Cancel() => Run("Cancel", () => _plugin.Cancel(Client!));

    [Command("mapreload"), RequireAdmin]
    public void Reload() => Run("Reload", () => _plugin.Reload(Client!));

    [Command("mapset"), RequireAdmin]
    public void Set(int id) => Run("AdminSet", () => _plugin.AdminSet(Client!, id));
}
