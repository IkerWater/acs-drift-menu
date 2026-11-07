using AssettoServer.Commands;
using AssettoServer.Commands.Attributes;
using JetBrains.Annotations;
using Qmmands;
using Serilog;

namespace AcsDriftServerPlugin;

/// <summary>Comandos de chat para probar el fantasma sin el menú. Solo administradores.</summary>
[UsedImplicitly(ImplicitUseKindFlags.Access, ImplicitUseTargetFlags.WithMembers)]
public class GhostCommandModule : ACModuleBase
{
    private readonly GhostService _ghosts;

    public GhostCommandModule(GhostService ghosts)
    {
        _ghosts = ghosts;
    }

    // Igual que en MapVoteCommandModule: registra el error completo y avisa al admin con un resumen.
    private void Run(string what, Action action)
    {
        try { action(); }
        catch (Exception ex)
        {
            var e = ex;
            var chain = new List<string>();
            while (e != null) { chain.Add($"{e.GetType().FullName}: {e.Message}"); e = e.InnerException; }
            Log.Error("ACS Drift Server: failure in {What}: {Chain}\n{Trace}", what, string.Join(" -> ", chain), ex.StackTrace ?? "");
            try { Client?.SendChatMessage($"[Ghost] Error: {ex.Message}"); } catch { /* nothing */ }
        }
    }

    [Command("ghostrec"), RequireAdmin]
    public void Record() => Run("StartRecording", () => _ghosts.StartRecording(Client!));

    [Command("ghoststop"), RequireAdmin]
    public void Stop() => Run("StopRecording", () => _ghosts.StopRecording(Client!));

    [Command("ghostcancel"), RequireAdmin]
    public void Cancel() => Run("CancelRecording", () => _ghosts.CancelRecording(Client!));

    [Command("ghostlist"), RequireAdmin]
    public void List() => Run("SendList", () => _ghosts.SendList(Client!));

    [Command("ghostplay"), RequireAdmin]
    public void Play(int id) => Run("Load", () => _ghosts.Load(Client!, id));

    [Command("ghostclear"), RequireAdmin]
    public void Clear() => Run("Unload", () => _ghosts.Unload(Client!));

    [Command("ghostdelete"), RequireAdmin]
    public void Delete(int id) => Run("Delete", () => _ghosts.Delete(Client!, id));
}
