import AnemoneJellyfin
@testable import AnemonePlayback
import Foundation
import Synchronization
import Testing

/// Closing live TV streams, with progress reporting alongside as every player has it.
@MainActor
struct LiveStreamClosingTests {
    private let engine = FakeEngine()
    private let server = LiveTVServerLog()

    /// Each request for a stream opens another live stream, as `isAutoOpenLiveStream` does;
    /// `isLive: false` hands out recordings' and films' streams, which have none.
    private func controller(isLive: Bool = true) -> PlaybackController {
        let server = server
        return PlaybackController(
            request: PlaybackRequest(.item("channel1")),
            engine: engine,
            features: [
                ProgressReporting { server.report($0) },
                LiveStreamClosing { server.close($0) },
            ],
            positionInterval: .milliseconds(10),
        ) { itemID, allowsDirect, _ in
            let number = server.open()
            return PlaybackStream(
                itemID: itemID,
                url: URL(filePath: "/\(itemID)/\(number)"),
                method: allowsDirect ? .directPlay : .transcode,
                playSessionID: "ps\(number)",
                liveStreamID: isLive ? "live\(number)" : nil,
            )
        }
    }

    @Test func `a live stream closed before playing is closed`() async {
        let playback = controller()
        await playback.start()

        await playback.stop()

        #expect(server.closed == ["live1"])
        #expect(server.stopReports.isEmpty)
    }

    @Test func `once under way, the stop report carries the live stream and it isn't closed again`() async {
        let playback = controller()
        await playback.start()
        engine.send(.ready)
        #expect(await eventually { server.reportCount == 1 })

        await playback.stop()

        #expect(server.stopReports.map(\.liveStreamID) == ["live1"])
        #expect(server.closed.isEmpty)
    }

    @Test func `a live stream that fails before playing is closed before the transcode opens another`() async {
        let playback = controller()
        await playback.start()

        engine.send(.failed(URLError(.cannotConnectToHost)))
        #expect(await eventually { engine.loads.count == 2 })

        #expect(server.closed == ["live1"])
        engine.send(.ready)
        #expect(await eventually { server.reportCount == 1 })
        await playback.stop()
        #expect(server.closed == ["live1"])
        #expect(server.stopReports.map(\.liveStreamID) == ["live2"])
    }

    @Test func `streams without a live stream close nothing`() async {
        let playback = controller(isLive: false)
        await playback.start()

        await playback.stop()

        #expect(server.closed.isEmpty)
    }
}

/// What the fake server was asked: streams opened, reports and closes.
private final class LiveTVServerLog: Sendable {
    private struct State {
        var opened = 0
        var closed: [String] = []
        var reports: [PlaybackReporter.Report] = []
    }

    private let state = Mutex(State())

    var closed: [String] {
        state.withLock(\.closed)
    }

    var reportCount: Int {
        state.withLock(\.reports.count)
    }

    var stopReports: [PlaybackStream] {
        state.withLock(\.reports).compactMap { report in
            if case let .stop(stream, _) = report {
                stream
            } else {
                nil
            }
        }
    }

    /// Opens another stream and returns its number, from 1.
    func open() -> Int {
        state.withLock { state in
            state.opened += 1
            return state.opened
        }
    }

    func close(_ id: String) {
        state.withLock { $0.closed.append(id) }
    }

    func report(_ report: PlaybackReporter.Report) {
        state.withLock { $0.reports.append(report) }
    }
}
