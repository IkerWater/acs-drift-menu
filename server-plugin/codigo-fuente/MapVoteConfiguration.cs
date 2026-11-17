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

    [YamlMember(Description = "Folder where ghost laps are saved (relative to the server folder), one subfolder per track and layout")]
    public string GhostsFolder { get; init; } = "cfg/ghosts";

    [YamlMember(Description = "Maximum length of a recorded ghost lap in seconds")]
    public int GhostMaxRecordSeconds { get; init; } = 600;

    [YamlMember(Description = "Seconds the ghost waits at the start line between laps")]
    public int GhostLoopGapSeconds { get; init; } = 3;

    [YamlMember(Description = "How many times per second the ghost position is sent to the clients (10-100)")]
    public int GhostPlaybackHz { get; init; } = 40;
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
        RuleFor(x => x.GhostsFolder).NotEmpty();
        RuleFor(x => x.GhostMaxRecordSeconds).InclusiveBetween(10, 3600);
        RuleFor(x => x.GhostLoopGapSeconds).GreaterThanOrEqualTo(0);
        RuleFor(x => x.GhostPlaybackHz).InclusiveBetween(10, 100);
    }
}
