import AnemoneJellyfin

/// Keeps the server up to date on a play session, as Wholphin's `TrackActivityPlaybackListener`
/// does. Reports go out one at a time, in order, so a stop never overtakes the start before it.
@MainActor
final class PlaybackReporter {
    enum Report: Hashable, Sendable {
        case start(PlaybackStream, PlaybackProgress)
        case progress(PlaybackStream, PlaybackProgress)
        case stop(PlaybackStream, Duration)
    }

    typealias Send = @Sendable (Report) async throws -> Void

    /// The session being reported on, from `start` until `stop`.
    private(set) var stream: PlaybackStream?
    private let send: Send
    private var queue: Task<Void, Never>?
    /// The progress report waiting to go out.
    private var waitingProgress: Task<Void, Never>?

    init(send: @escaping Send) {
        self.send = send
    }

    func start(_ stream: PlaybackStream, at progress: PlaybackProgress) {
        self.stream = stream
        enqueue(.start(stream, progress))
    }

    /// Skipped outside a session, and while the last progress report is still waiting to go
    /// out, so a slow server doesn't pile them up.
    func progress(_ progress: PlaybackProgress) {
        guard let stream, waitingProgress == nil else { return }
        waitingProgress = enqueue(.progress(stream, progress)) { [weak self] in
            self?.waitingProgress = nil
        }
    }

    /// Ends the session, and returns once every report has gone out or failed.
    func stop(at position: Duration) async {
        if let stream {
            self.stream = nil
            // The stop carries the latest position, so a progress report still waiting on a slow
            // server is dropped rather than holding it up.
            waitingProgress?.cancel()
            enqueue(.stop(stream, position))
        }
        await queue?.value
    }

    @discardableResult
    private func enqueue(_ report: Report, then done: (@MainActor () -> Void)? = nil) -> Task<Void, Never> {
        let previous = queue
        let send = send
        let task = Task {
            await previous?.value
            // Like Wholphin, a report that fails is dropped; the next one carries the position.
            try? await send(report)
            done?()
        }
        queue = task
        return task
    }
}
