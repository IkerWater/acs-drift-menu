using AssettoServer.Server.Configuration;
using FluentValidation;
using JetBrains.Annotations;

namespace MapVotePlugin;

public enum MapRestartMode
{
    /// <summary>El plugin cierra AssettoServer; el lanzador (start_server.ps1/.sh) lo vuelve a arrancar.</summary>
    Exit,
    /// <summary>El plugin solo crea un fichero "flag"; un reiniciador externo hace el resto.</summary>
    File
}

[UsedImplicitly(ImplicitUseKindFlags.Assign, ImplicitUseTargetFlags.WithMembers)]
public class MapVoteConfiguration : IValidateConfiguration<MapVoteConfigurationValidator>
{
    /// <summary>Carpeta con los circuitos instalados en el servidor (relativa al directorio de trabajo).</summary>
    public string TracksFolder { get; init; } = "content/tracks";

    public int VoteDurationSeconds { get; init; } = 60;
    public int CooldownSeconds { get; init; } = 120;

    /// <summary>Segundos entre aprobar la votacion y reiniciar el servidor.</summary>
    public int ChangeDelaySeconds { get; init; } = 10;

    /// <summary>Si es true, quien propone el cambio cuenta como voto a favor.</summary>
    public bool ProposerVotesYes { get; init; } = true;

    /// <summary>Fichero donde se guarda el mapa elegido (lo lee el lanzador).</summary>
    public string SelectionFile { get; init; } = "map_selection.json";

    public MapRestartMode RestartMode { get; init; } = MapRestartMode.Exit;
    public string RestartFlagFile { get; init; } = "map_restart.flag";

    /// <summary>Carpetas de circuito que no deben aparecer en la lista.</summary>
    public List<string> ExcludeTracks { get; init; } = new();
}

public class MapVoteConfigurationValidator : AbstractValidator<MapVoteConfiguration>
{
    public MapVoteConfigurationValidator()
    {
        RuleFor(x => x.VoteDurationSeconds).GreaterThan(0);
        RuleFor(x => x.CooldownSeconds).GreaterThanOrEqualTo(0);
        RuleFor(x => x.ChangeDelaySeconds).GreaterThanOrEqualTo(0);
        RuleFor(x => x.TracksFolder).NotEmpty();
    }
}
