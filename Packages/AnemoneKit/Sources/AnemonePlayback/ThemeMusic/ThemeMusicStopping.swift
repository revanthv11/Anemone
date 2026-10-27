/// Holds theme music back while a video plays, as Wholphin stops `ThemeSongPlayer` when its
/// player opens, and lets the page's theme play again once the player is done with it.
@MainActor
public final class ThemeMusicStopping: PlaybackFeature {
    private let music: ThemeMusic

    public init(music: ThemeMusic = .shared) {
        self.music = music
    }

    public func handle(_ event: PlaybackEvent, in controller: PlaybackController) async {
        switch event {
        case .loaded:
            music.videoStarted()
        case .stopped:
            // The last session: the player closed, or the queue ended and it's closing.
            if controller.isStopped || controller.hasEnded {
                music.videoClosed()
            }
        case .failed:
            // Nothing more will play: the player shows the error over the page.
            if case .failed = controller.state {
                music.videoClosed()
            }
        case .started, .position, .paused, .resumed, .ended:
            break
        }
    }
}
