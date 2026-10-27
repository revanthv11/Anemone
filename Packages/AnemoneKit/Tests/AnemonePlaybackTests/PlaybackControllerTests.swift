import AnemoneJellyfin
@testable import AnemonePlayback
import Foundation
import Testing

/// Playing a queue through an engine, and what features hear about it.
@MainActor
struct PlaybackControllerTests {
    private let engine = FakeEngine()
    private let log = EventLog()

    private func controller(
        _ entries: [PlaybackQueue.Entry] = [.item("m1", from: .seconds(30))],
        streams: FakeStreams = FakeStreams(),
    ) throws -> PlaybackController {
        try PlaybackController(
            request: PlaybackRequest(queue: #require(PlaybackQueue(entries: entries))),
            engine: engine,
            features: [log],
            positionInterval: .milliseconds(10),
            loadStream: streams.load,
        )
    }

    /// Starts `playback` and lets the engine get it under way.
    private func play(_ playback: PlaybackController) async {
        await playback.start()
        engine.send(.ready)
        _ = await eventually { log.events.contains { $0.hasPrefix("started") } }
    }

    @Test func `a queue of one plays its entry from its start position`() async throws {
        let streams = FakeStreams()
        let playback = try controller(streams: streams)

        await playback.start()
        engine.send(.ready)
        #expect(await eventually { engine.isPlaying })

        #expect(streams.received == [.init(itemID: "m1", allowsDirect: true, mediaSourceID: nil)])
        let load = try #require(engine.loads.first)
        #expect(load.url == FakeStreams.stream("m1", method: .directPlay).url)
        #expect(load.position == .seconds(30))
        #expect(load.metadata.title == "Title m1")
        #expect(playback.queue.current.itemID == "m1")
        #expect(playback.queue.next == nil)
        #expect(playback.feature(EventLog.self) === log)
        #expect(playback.feature(ProgressReporting.self) == nil)
        #expect(playback.state.isPlaying)
    }

    @Test func `features hear each event in order`() async throws {
        let playback = try controller()

        await play(playback)
        engine.currentTime = .seconds(31)
        #expect(await eventually { log.events.contains("position") })
        engine.pause()
        #expect(await eventually { log.events.contains { $0.hasPrefix("paused") } })
        engine.play()
        #expect(await eventually { log.events.contains { $0.hasPrefix("resumed") } })
        // Waiting for data isn't a pause.
        engine.send(.status(.waiting))
        engine.send(.status(.playing))
        await playback.stop()

        #expect(log.events.filter { $0 != "position" } == [
            "loaded m1 directPlay",
            "started 0.0 seconds",
            "paused 31.0 seconds",
            "resumed 31.0 seconds",
            "stopped 31.0 seconds",
        ])
        #expect(engine.isStopped)
    }

    @Test func `the player closes at the end of the queue`() async throws {
        let playback = try controller()
        await play(playback)

        engine.send(.ended)

        #expect(await eventually { playback.hasEnded })
        #expect(await eventually { log.events.last == "stopped 100.0 seconds" })
        #expect(log.events.suffix(2) == ["ended", "stopped 100.0 seconds"])
        // Closing the player afterwards doesn't end the session twice.
        await playback.stop()
        #expect(log.events.count(where: { $0.hasPrefix("stopped") }) == 1)
    }

    @Test func `a feature can play the next entry when one ends`() async throws {
        let streams = FakeStreams()
        let playback = try controller([.item("e1"), .item("e2")], streams: streams)
        log.onEvent = { event, controller in
            if case .ended = event {
                controller.playNext()
            }
        }
        await play(playback)
        engine.currentTime = .seconds(100)

        engine.send(.ended)

        #expect(await eventually { engine.loads.count == 2 })
        #expect(playback.queue.current.itemID == "e2")
        #expect(streams.received.last == .init(itemID: "e2", allowsDirect: true, mediaSourceID: nil))
        #expect(log.events.suffix(3) == ["ended", "stopped 100.0 seconds", "loaded e2 directPlay"])
        #expect(!playback.hasEnded)
    }

    @Test func `a feature can keep the player open at the end`() async throws {
        let playback = try controller()
        playback.closesAtEnd = false
        await play(playback)

        engine.send(.ended)
        #expect(await eventually { log.events.last == "stopped 100.0 seconds" })
        #expect(!playback.hasEnded)

        playback.finish()
        #expect(playback.hasEnded)
    }

    @Test func `a direct play that fails is retried as a transcode from the same position`() async throws {
        let streams = FakeStreams()
        let playback = try controller(streams: streams)
        await play(playback)
        engine.currentTime = .seconds(45)

        engine.send(.failed(PlayerError.streamFailed(underlying: nil)))

        #expect(await eventually { engine.loads.count == 2 })
        #expect(streams.received.last == .init(itemID: "m1", allowsDirect: false, mediaSourceID: "src-m1"))
        #expect(engine.loads.last?.position == .seconds(45))
        #expect(log.events.suffix(3) == ["failed", "stopped 45.0 seconds", "loaded m1 transcode"])
    }

    @Test func `a transcode that fails shows the error`() async throws {
        let playback = try controller()
        await play(playback)
        engine.send(.failed(PlayerError.streamFailed(underlying: nil)))
        #expect(await eventually { engine.loads.count == 2 })
        engine.send(.ready)

        engine.send(.failed(PlayerError.streamFailed(underlying: nil)))

        #expect(await eventually { playback.state.isFailed })
        #expect(engine.loads.count == 2)
    }

    @Test func `a stream the server won't offer shows the error`() async throws {
        let playback = try controller(streams: FakeStreams(failingWith: PlaybackError.notAllowed))

        await playback.start()

        guard case let .failed(error) = playback.state else {
            Issue.record("failed, not \(playback.state)")
            return
        }
        #expect(error as? PlaybackError == .notAllowed)
        #expect(log.events == ["failed"])
        #expect(engine.loads.isEmpty)
    }

    @Test func `shuffling plays the queue in another order`() throws {
        let entries = (1 ... 20).map { PlaybackQueue.Entry.item("e\($0)") }
        let playback = try PlaybackController(
            request: PlaybackRequest(queue: #require(PlaybackQueue(entries: entries)), shuffles: true),
            engine: engine,
            features: [],
        ) { _, _, _ in throw CancellationError() }

        #expect(playback.queue.currentIndex == 0)
        #expect(Set(playback.queue.entries.map(\.itemID)) == Set(entries.map(\.itemID)))
        #expect(playback.queue.entries != entries)
    }
}

private extension PlaybackController.State {
    var isPlaying: Bool {
        if case .playing = self {
            true
        } else {
            false
        }
    }

    var isFailed: Bool {
        if case .failed = self {
            true
        } else {
            false
        }
    }
}
