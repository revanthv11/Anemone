import AnemoneJellyfin

public extension PlaybackController {
    /// The features every player gets, in the order they hear events. A new feature registers
    /// itself here with one line.
    static func features(for session: JellyfinSession) -> [any PlaybackFeature] {
        [
            ProgressReporting(session: session),
            SegmentSkipping(session: session),
            UpNext(),
            PlaybackDetails(session: session),
            NowPlaying(),
            SkipBackOnResume(),
            PlaybackLifecycle(),
            DisplayCriteriaMatching(),
        ]
    }
}
