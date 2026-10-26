import AnemoneJellyfin
@testable import AnemonePlayback
import Foundation
import Synchronization
import Testing

/// The order and pace of reports to the server.
@MainActor
struct PlaybackReporterTests {
    private static let stream = PlaybackStream(
        itemID: "m1",
        url: URL(filePath: "/"),
        method: .directPlay,
        playSessionID: "ps1",
    )

    private static func progress(_ seconds: Int, paused: Bool = false) -> PlaybackProgress {
        PlaybackProgress(position: .seconds(seconds), isPaused: paused)
    }

    @Test func `reports go out in order`() async {
        let server = FakeServer()
        let reporter = PlaybackReporter(send: server.send)

        reporter.start(Self.stream, at: Self.progress(0))
        reporter.progress(Self.progress(5))
        await server.waitFor(count: 2)
        await reporter.stop(at: .seconds(7))

        #expect(server.received == [
            .start(Self.stream, Self.progress(0)),
            .progress(Self.stream, Self.progress(5)),
            .stop(Self.stream, .seconds(7)),
        ])
    }

    @Test func `progress waits for the one before it`() async {
        let server = FakeServer(delay: .milliseconds(50))
        let reporter = PlaybackReporter(send: server.send)

        reporter.start(Self.stream, at: Self.progress(0))
        reporter.progress(Self.progress(5))
        // The server hasn't heard about 5 s yet, so 10 s is dropped.
        reporter.progress(Self.progress(10, paused: true))
        await server.waitFor(count: 2)
        await reporter.stop(at: .seconds(12))
        reporter.progress(Self.progress(15))

        #expect(server.received == [
            .start(Self.stream, Self.progress(0)),
            .progress(Self.stream, Self.progress(5)),
            .stop(Self.stream, .seconds(12)),
        ])
    }

    @Test func `a stuck progress report doesn't hold up the stop`() async {
        let server = FakeServer(progressDelay: .seconds(30))
        let reporter = PlaybackReporter(send: server.send)

        reporter.start(Self.stream, at: Self.progress(0))
        reporter.progress(Self.progress(5))
        await server.waitFor(count: 1)
        let elapsed = await ContinuousClock().measure {
            await reporter.stop(at: .seconds(6))
        }

        #expect(elapsed < .seconds(5))
        #expect(server.received == [.start(Self.stream, Self.progress(0)), .stop(Self.stream, .seconds(6))])
    }

    @Test func `nothing is reported outside a session`() async {
        let server = FakeServer()
        let reporter = PlaybackReporter(send: server.send)

        reporter.progress(Self.progress(5))
        await reporter.stop(at: .seconds(5))

        #expect(server.received.isEmpty)
    }

    @Test func `a failed report doesn't hold up the rest`() async {
        let server = FakeServer(failing: true)
        let reporter = PlaybackReporter(send: server.send)

        reporter.start(Self.stream, at: Self.progress(0))
        reporter.progress(Self.progress(5))
        await server.waitFor(count: 2)
        await reporter.stop(at: .seconds(6))

        #expect(server.received.count == 3)
    }
}

/// Records reports, optionally slowly or failing each one. A report that's cancelled while
/// it's slow isn't recorded, as a cancelled request never reaches a real server.
private final class FakeServer: Sendable {
    private let reports = Mutex<[PlaybackReporter.Report]>([])
    private let delay: Duration
    private let progressDelay: Duration?
    private let failing: Bool

    init(delay: Duration = .zero, progressDelay: Duration? = nil, failing: Bool = false) {
        self.delay = delay
        self.progressDelay = progressDelay
        self.failing = failing
    }

    var received: [PlaybackReporter.Report] {
        reports.withLock(\.self)
    }

    /// Waits until the server has had `count` reports.
    func waitFor(count: Int) async {
        while received.count < count {
            await Task.yield()
        }
    }

    var send: PlaybackReporter.Send {
        { [self] report in
            if case .progress = report, let progressDelay {
                try await Task.sleep(for: progressDelay)
            } else {
                try await Task.sleep(for: delay)
            }
            reports.withLock { $0.append(report) }
            if failing {
                throw URLError(.cannotConnectToHost)
            }
        }
    }
}
