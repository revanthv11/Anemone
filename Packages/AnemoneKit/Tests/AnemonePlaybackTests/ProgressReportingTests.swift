import AnemoneJellyfin
@testable import AnemonePlayback
import Foundation
import Synchronization
import Testing

/// The progress-reporting feature, driven by a controller with a fake engine.
@MainActor
struct ProgressReportingTests {
    private let engine = FakeEngine()
    private let reports = ReportLog()

    private var received: [PlaybackReporter.Report] {
        reports.received
    }

    private func controller() -> PlaybackController {
        let reports = reports
        let reporting = ProgressReporting { report in
            reports.append(report)
        }
        return PlaybackController(
            request: PlaybackRequest(.item("m1")),
            engine: engine,
            features: [reporting],
            positionInterval: .milliseconds(10),
            loadStream: FakeStreams().load,
        )
    }

    private static let stream = FakeStreams.stream("m1", method: .directPlay)

    private static func progress(_ seconds: Int, paused: Bool = false) -> PlaybackProgress {
        PlaybackProgress(position: .seconds(seconds), isPaused: paused)
    }

    @Test func `reports start, progress every five positions, pauses and the stop`() async {
        let playback = controller()
        await playback.start()
        engine.send(.ready)
        #expect(await eventually { received.count == 1 })
        engine.currentTime = .seconds(12)

        #expect(await eventually { received.count == 2 })
        engine.pause()
        #expect(await eventually { received.count == 3 })
        await playback.stop()

        #expect(received.first == .start(Self.stream, Self.progress(0)))
        #expect(received.dropFirst().first == .progress(Self.stream, Self.progress(12)))
        #expect(received.contains(.progress(Self.stream, Self.progress(12, paused: true))))
        #expect(received.last == .stop(Self.stream, .seconds(12)))
    }

    @Test func `nothing is saved at the very start`() async {
        let playback = controller()
        await playback.start()
        engine.send(.ready)
        #expect(await eventually { received.count == 1 })

        engine.pause()
        try? await Task.sleep(for: .milliseconds(100))
        await playback.stop()

        #expect(received == [.start(Self.stream, Self.progress(0)), .stop(Self.stream, .zero)])
    }
}

/// The reports the server got.
private final class ReportLog: Sendable {
    private let reports = Mutex<[PlaybackReporter.Report]>([])

    var received: [PlaybackReporter.Report] {
        reports.withLock(\.self)
    }

    func append(_ report: PlaybackReporter.Report) {
        reports.withLock { $0.append(report) }
    }
}
