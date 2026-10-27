/// Stops the music when a video starts, as Wholphin's video player stops `MusicService`.
@MainActor
public final class MusicStopping: PlaybackFeature {
    public init() {}

    public func handle(_ event: PlaybackEvent, in _: PlaybackController) async {
        if case .loaded = event {
            MusicPlayer.active?.stop()
        }
    }
}
