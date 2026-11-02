using AssettoServer.Server.Configuration;
using FluentValidation;
using JetBrains.Annotations;
using YamlDotNet.Serialization;

namespace AcsDriftServerPlugin;

[UsedImplicitly(ImplicitUseKindFlags.Assign, ImplicitUseTargetFlags.WithMembers)]
public class MapVoteConfiguration : IValidateConfiguration<MapVoteConfigurationValidator>
{
    [YamlMember(Description = "Folder containing installed tracks (relative to the server folder)")]
    public string TracksFolder { get; init; } = "content/tracks";

    [YamlMember(Description = "Vote duration in seconds")]
    public int VoteDurationSeconds { get; init; } = 60;

    [YamlMember(Description = "Cooldown in seconds after a vote starts before another can be proposed")]
    public int CooldownSeconds { get; init; } = 120;

    [YamlMember(Description = "Seconds between a vote passing and announcing the change")]
    public int ChangeDelaySeconds { get; init; } = 10;

    [YamlMember(Description = "Seconds between the announcement and restart")]
    public int TransitionSeconds { get; init; } = 5;

    [YamlMember(Description = "Whether the proposer counts as a vote in favor")]
    public bool ProposerVotesYes { get; init; } = true;

    [YamlMember(Description = "Automatically reconnect players after track changes (requires EnableClientMessages)")]
    public bool EnableReconnect { get; init; } = true;

    [YamlMember(Description = "Change the track in all presets in addition to cfg/ (presets are not changed by default)")]
    public bool ApplyToAllPresets { get; init; } = false;

    [YamlMember(Description = "Track folders to exclude from the list")]
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
