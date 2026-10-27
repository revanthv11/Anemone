/// Holds theme music back while a video plays, as Wholphin stops `ThemeSongPlayer` when its
/// player opens, and lets the page's theme play again once the player is done with it.
@MainActor
public final class ThemeMusicStopping: PlaybackFeature {
    private let music: ThemeMusic
    /// The player it lets theme music go for when it closes.
    private weak var controller: PlaybackController?

    public init(music: ThemeMusic = .shared) {
        self.music = music
    }

    public func handle(_ event: PlaybackEvent, in controller: PlaybackController) async {
        switch event {
        case .loaded:
            music.videoStarted()
            releaseWhenClosed(controller)
        case .failed:
            // Nothing more will play: the player shows the error over the page.
            if case .failed = controller.state {
                music.videoClosed()
            }
        case .started, .position, .paused, .resumed, .ended, .stopped:
            break
        }
    }

    /// Once for each player, when it closes rather than at a `stopped`: it can close after the
    /// last entry's session ended, as when Up Next or "Still watching?" is cancelled over the
    /// last frame, and no `stopped` comes then.
    private func releaseWhenClosed(_ controller: PlaybackController) {
        guard self.controller !== controller else { return }
        self.controller = controller
        let music = music
        controller.whenStopped {
            music.videoClosed()
        }
    }
}
