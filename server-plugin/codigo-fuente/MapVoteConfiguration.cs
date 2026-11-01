using AssettoServer.Server.Configuration;
using FluentValidation;
using JetBrains.Annotations;
using YamlDotNet.Serialization;

namespace AcsDriftServerPlugin;

[UsedImplicitly(ImplicitUseKindFlags.Assign, ImplicitUseTargetFlags.WithMembers)]
public class MapVoteConfiguration : IValidateConfiguration<MapVoteConfigurationValidator>
{
    [YamlMember(Description = "Carpeta con los circuitos instalados (relativa a la carpeta del servidor)")]
    public string TracksFolder { get; init; } = "content/tracks";

    [YamlMember(Description = "Segundos que dura una votación")]
    public int VoteDurationSeconds { get; init; } = 60;

    [YamlMember(Description = "Segundos de espera, desde que empieza una votación, hasta poder proponer otra")]
    public int CooldownSeconds { get; init; } = 120;

    [YamlMember(Description = "Segundos entre aprobar la votación y avisar del cambio")]
    public int ChangeDelaySeconds { get; init; } = 10;

    [YamlMember(Description = "Segundos entre el aviso y el reinicio (los jugadores se reconectan solos)")]
    public int TransitionSeconds { get; init; } = 5;

    [YamlMember(Description = "Quien propone el cambio cuenta como voto a favor")]
    public bool ProposerVotesYes { get; init; } = true;

    [YamlMember(Description = "Reconectar a los jugadores automáticamente (requiere EnableClientMessages); si es false se les expulsa con un aviso")]
    public bool EnableReconnect { get; init; } = true;

    [YamlMember(Description = "Además de cfg/, cambiar el circuito en todos los presets (por defecto los presets no se tocan)")]
    public bool ApplyToAllPresets { get; init; } = false;

    [YamlMember(Description = "Carpetas de circuito que no deben aparecer en la lista")]
    public List<string> ExcludeTracks { get; init; } = [];
}

public class MapVoteConfigurationValidator : AbstractValidator<MapVoteConfiguration>
{
    public MapVoteConfigurationValidator()
    {
        RuleFor(x => x.VoteDurationSeconds).GreaterThanOrEqualTo(10);
        RuleFor(x => x.CooldownSeconds).GreaterThanOrEqualTo(0);
        RuleFor(x => x.ChangeDelaySeconds).GreaterThanOrEqualTo(0);
        RuleFor(x => x.TransitionSeconds).GreaterThanOrEqualTo(2);
        RuleFor(x => x.TracksFolder).NotEmpty();
    }
}
