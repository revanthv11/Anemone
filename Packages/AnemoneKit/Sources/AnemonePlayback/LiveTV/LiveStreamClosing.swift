import AnemoneJellyfin

/// Frees the tuner after live TV. Asking how to play a channel opens a live stream on the server
/// (`isAutoOpenLiveStream`), which stays open until something closes it.
///
/// Once playback is under way, `ProgressReporting`'s stop report carries the live stream's ID and
/// the server closes it then. A session that ends before that (the stream failed, was replaced
/// by a transcode, or the player closed while loading) sends no stop report, so this closes the
/// stream itself. Closing it after the stop report too would close it twice, which could cut off
/// someone else sharing the tuner's stream. Adapted from Swiftfin's
/// `MediaProgressReporter.discard`.
@MainActor
public final class LiveStreamClosing: PlaybackFeature {
    typealias Close = @Sendable (String) async throws -> Void

    private let close: Close
    /// The loaded stream's live stream, until its session ends.
    private var liveStreamID: String?
    private var isUnderWay = false

    public convenience init(session: JellyfinSession) {
        self.init { id in
            try await session.closeLiveStream(id: id)
        }
    }

    init(close: @escaping Close) {
        self.close = close
    }

    public func handle(_ event: PlaybackEvent, in _: PlaybackController) async {
        switch event {
        case let .loaded(stream, _):
            liveStreamID = stream.liveStreamID
            isUnderWay = false
        case .started:
            isUnderWay = true
        case .stopped:
            defer { liveStreamID = nil }
            guard let liveStreamID, !isUnderWay else { return }
            // Like the stop report, a close that fails is dropped; the server times the stream out.
            try? await close(liveStreamID)
        case .position, .paused, .resumed, .ended, .failed:
            break
        }
    }
}
