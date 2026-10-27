import AnemoneJellyfin

public extension PlaybackController {
    /// The features every player gets, in the order they hear events. A new feature registers
    /// itself here with one line.
    static func features(for session: JellyfinSession) -> [any PlaybackFeature] {
        [
            ProgressReporting(session: session),
            SegmentSkipping(session: session),
            UpNext(),
            // Before track selection, which says what it draws once it knows the stream.
            DrawnSubtitles(session: session),
            TrackSelection(session: session),
            PlaybackDetails(session: session),
            LiveStreamClosing(session: session),
            // Before Now Playing: stopped music gives up Now Playing and the remote's commands.
            MusicStopping(),
            NowPlaying(),
            SkipBackOnResume(),
            PlaybackLifecycle(),
            DisplayCriteriaMatching(),
            PlaybackSpeedMenu(),
            MPVSubtitleMenus(session: session),
            MPVExternalSubtitles(session: session),
        ]
    }
}
