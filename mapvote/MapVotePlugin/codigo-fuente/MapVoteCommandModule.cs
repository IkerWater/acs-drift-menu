using AssettoServer.Commands;
using AssettoServer.Commands.Attributes;
using JetBrains.Annotations;
using Qmmands;
using Serilog;

namespace MapVotePlugin;

[UsedImplicitly(ImplicitUseKindFlags.Access, ImplicitUseTargetFlags.WithMembers)]
public class MapVoteCommandModule : ACModuleBase
{
    private readonly MapVotePlugin _plugin;

    public MapVoteCommandModule(MapVotePlugin plugin)
    {
        _plugin = plugin;
    }

    // Registra el error completo en el log (y lo resume al jugador) en vez del genérico de AssettoServer
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
            Log.Error("MapVote: fallo en {What}: {Chain}\n{Trace}", what, string.Join(" -> ", chain), trace);
            try { Client?.SendChatMessage($"[Mapa] Error: {ex.Message}"); } catch { /* nada */ }
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
