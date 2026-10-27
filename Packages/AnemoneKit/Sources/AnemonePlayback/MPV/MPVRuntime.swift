import AnemoneJellyfin

/// Tells the MPV engine how long the server says each stream runs (PlaybackInfo's
/// `RunTimeTicks`), so the end of a file whose duration libmpv only estimates, such as a TS or
/// AVI file played directly, isn't taken for a cut-off and retried as a transcode (see
/// `MPVPlayerEngine.isRealEnd(at:of:runtime:)`).
@MainActor
public final class MPVRuntime: PlaybackFeature {
    public init() {}

    public func handle(_ event: PlaybackEvent, in controller: PlaybackController) async {
        let stream: PlaybackStream
        switch event {
        case let .loaded(loaded, _): stream = loaded
        case let .reloaded(reloaded): stream = reloaded
        default: return
        }
        // The engine leaves it if another stream has replaced this one meanwhile.
        controller.engine.mpv?.setRuntime(stream.runtime, forStreamFrom: stream.url)
    }
}
