import AnemoneJellyfin

/// Keeps the server up to date on each entry's play session, like Wholphin: the start report
/// once playback is under way, then progress every 5 s and whenever it pauses or resumes, and the
/// stop report with the final position. `PlaybackReporter` keeps the reports in order.
@MainActor
public final class ProgressReporting: PlaybackFeature {
    /// How often progress is saved while playing, as in Wholphin, counted in position events.
    static let positionsPerReport = 5

    private let reporter: PlaybackReporter
    /// The loaded stream, which the start report is about.
    private var stream: PlaybackStream?
    private var positions = 0

    public convenience init(session: JellyfinSession) {
        self.init { report in
            switch report {
            case let .start(stream, progress):
                try await session.reportPlaybackStart(stream, at: progress)
            case let .progress(stream, progress):
                try await session.reportPlaybackProgress(stream, at: progress)
            case let .stop(stream, position):
                try await session.reportPlaybackStopped(stream, at: position)
            }
        }
    }

    init(send: @escaping PlaybackReporter.Send) {
        reporter = PlaybackReporter(send: send)
    }

    public func handle(_ event: PlaybackEvent, in _: PlaybackController) async {
        switch event {
        case let .loaded(stream, _):
            self.stream = stream
        case let .started(progress):
            positions = 0
            if let stream {
                reporter.start(stream, at: progress)
            }
        case let .position(progress):
            positions += 1
            if positions.isMultiple(of: Self.positionsPerReport) {
                save(progress)
            }
        case let .paused(progress), let .resumed(progress):
            save(progress)
        case let .stopped(position):
            stream = nil
            await reporter.stop(at: position)
        case .ended, .failed:
            break
        }
    }

    /// Wholphin doesn't save a position at the very start.
    private func save(_ progress: PlaybackProgress) {
        if progress.position > .zero {
            reporter.progress(progress)
        }
    }
}
