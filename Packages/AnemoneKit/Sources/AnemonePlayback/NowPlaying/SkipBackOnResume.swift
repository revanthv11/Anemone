import AnemoneCore

/// Goes back a few seconds whenever playback resumes after a pause, so the viewer picks up the
/// thread. Ported from Wholphin's `MediaSessionPlayer`, which seeks back by its
/// `skipBackOnResume` setting each time the player is told to play.
///
/// Every resume counts, whatever asked for it: the remote, Now Playing, or coming back to the
/// app after it went to the background mid-play.
@MainActor
public final class SkipBackOnResume: PlaybackFeature {
    /// The setting, read at each resume, so a change applies at once.
    typealias Setting = @MainActor () -> Duration

    private let setting: Setting

    public convenience init() {
        self.init { .seconds(Preferences.skipBackOnResume.value()) }
    }

    init(setting: @escaping Setting) {
        self.setting = setting
    }

    public func handle(_ event: PlaybackEvent, in controller: PlaybackController) async {
        guard case let .resumed(progress) = event else { return }
        let skip = setting()
        guard skip > .zero else { return }
        let engine = controller.engine
        let target = max(progress.position - skip, .zero)
        Task {
            _ = await engine.seek(to: target)
        }
    }
}

public extension Preferences {
    /// Wholphin's `skipBackOnResumeSeconds`: whole seconds from 0 (off, its default) to 10.
    static let skipBackOnResume = Preference("skipBackOnResumeSeconds", default: 0)
}
