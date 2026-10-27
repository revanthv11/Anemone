@testable import AnemonePlayback
import Foundation
import Testing

/// How a stream ends in the MPV engine: at its end, cut off partway, or unloaded by libmpv for
/// some other reason, which mustn't leave it loading forever.
@MainActor
struct MPVEngineEndTests {
    /// With `keep-open`, a read or network error partway reaches libmpv as the end of the file:
    /// paused on the last frame it got, `eof-reached`, and no end-file error.
    @Test func `an end of the file well before its duration fails the stream`() async throws {
        let client = FakeMPVClient()
        let engine = MPVPlayerEngine.testing(client)
        let log = engine.loadAndStart(on: client)
        client.properties["time-pos"] = "100"
        client.properties["duration"] = "600"

        engine.handle(.property("eof-reached", .flag(true)))

        #expect(await eventually { log.isFinished })
        #expect(log.events == ["paused", "ready", "paused", "failed"])
        let error = try #require(log.errors.first as? PlayerError)
        guard case let .streamFailed(underlying) = error else {
            Issue.record("expected a stream failure, got \(error)")
            return
        }
        #expect(underlying as? MPVError == .endedEarly)
    }

    @Test func `an end of the file near its duration is the end`() async {
        let client = FakeMPVClient()
        let engine = MPVPlayerEngine.testing(client)
        let log = engine.loadAndStart(on: client)
        client.properties["time-pos"] = "594.5"
        client.properties["duration"] = "600"

        engine.handle(.property("eof-reached", .flag(true)))

        #expect(await eventually { log.events.last == "ended" })
        #expect(!log.isFinished)
    }

    @Test func `the end is the last 2 percent, at least 10 s, or anywhere without a duration`() {
        #expect(MPVPlayerEngine.isRealEnd(at: .seconds(290), of: .seconds(300)))
        #expect(!MPVPlayerEngine.isRealEnd(at: .seconds(289), of: .seconds(300)))
        #expect(MPVPlayerEngine.isRealEnd(at: .seconds(7056), of: .seconds(7200)))
        #expect(!MPVPlayerEngine.isRealEnd(at: .seconds(7055), of: .seconds(7200)))
        #expect(MPVPlayerEngine.isRealEnd(at: .seconds(30), of: nil))
    }

    /// Wholphin's retry as a transcode, for a direct play that stops partway, rather than Up
    /// Next and a session ended at the duration.
    @Test func `a direct play cut off partway is retried as a transcode from where it stopped`() async {
        let client = FakeMPVClient()
        let engine = MPVPlayerEngine.testing(client)
        let streams = FakeStreams()
        let features = EventLog()
        let playback = PlaybackController(
            request: PlaybackRequest(.item("m1")),
            engine: engine,
            features: [features],
            positionInterval: .seconds(60),
            loadStream: streams.load,
        )
        await playback.start()
        engine.start(client.entries[0])
        #expect(await eventually { playback.state.isPlaying })
        client.properties["time-pos"] = "100"
        client.properties["duration"] = "600"

        engine.handle(.property("eof-reached", .flag(true)))

        #expect(await eventually { features.events.contains("loaded m1 transcode") })
        #expect(client.entries.count == 2)
        #expect(streams.received.last?.allowsDirect == false)
        #expect(client.commands.last?[1] == FakeStreams.stream("m1", method: .transcode).url.absoluteString)
        #expect(client.commands.last?.last?.hasSuffix("start=100.000") == true)
        #expect(!features.events.contains("ended"))
        await playback.stop()
    }

    @Test func `a playlist plays on from its first entry`() async {
        let client = FakeMPVClient()
        let engine = MPVPlayerEngine.testing(client)
        let log = engine.loadLog()

        engine.handle(.startFile(entry: 1))
        engine.handle(.endFile(entry: 1, .redirected(next: 7)))
        engine.start(7)

        #expect(await eventually { log.events == ["paused", "ready", "paused"] })
    }

    @Test func `an empty playlist fails`() async {
        let client = FakeMPVClient()
        let engine = MPVPlayerEngine.testing(client)
        let log = engine.loadLog()

        engine.handle(.startFile(entry: 1))
        engine.handle(.endFile(entry: 1, .redirected(next: nil)))

        #expect(await eventually { log.isFinished })
        #expect(log.events == ["paused", "failed"])
    }

    @Test(arguments: [MPVEndReason.stopped, .quit])
    func `libmpv unloading the loading stream unasked fails it`(reason: MPVEndReason) async {
        let client = FakeMPVClient()
        let engine = MPVPlayerEngine.testing(client)
        let log = engine.loadLog()

        engine.handle(.startFile(entry: 1))
        engine.handle(.endFile(entry: 1, reason))

        #expect(await eventually { log.isFinished })
        #expect(log.events == ["paused", "failed"])
    }

    @Test func `a file libmpv unloads at its end before it ever played fails`() async {
        let client = FakeMPVClient()
        let engine = MPVPlayerEngine.testing(client)
        let log = engine.loadLog()

        engine.handle(.startFile(entry: 1))
        engine.handle(.endFile(entry: 1, .endOfFile))

        #expect(await eventually { log.isFinished })
        #expect(log.events == ["paused", "failed"])
    }

    @Test func `libmpv shutting down fails the stream playing`() async {
        let client = FakeMPVClient()
        let engine = MPVPlayerEngine.testing(client)
        let log = engine.loadAndStart(on: client)

        engine.handle(.shutdown)

        #expect(await eventually { log.isFinished })
        #expect(log.events == ["paused", "ready", "paused", "failed"])
    }

    @Test func `stopping, or loading another stream, ends the stream without a failure`() async {
        let client = FakeMPVClient()
        let engine = MPVPlayerEngine.testing(client)
        let first = engine.loadAndStart(on: client)
        let second = engine.loadAndStart(on: client, "/next.mkv")
        engine.handle(.endFile(entry: 1, .stopped))

        engine.stop()
        engine.handle(.endFile(entry: 2, .stopped))

        #expect(await eventually { first.isFinished && second.isFinished })
        #expect(first.events == ["paused", "ready", "paused"])
        #expect(second.events == ["paused", "ready", "paused"])
    }

    @Test func `a stream that played to the end isn't failed when libmpv unloads it`() async {
        let client = FakeMPVClient()
        let engine = MPVPlayerEngine.testing(client)
        let log = engine.loadAndStart(on: client)

        engine.handle(.endFile(entry: 1, .endOfFile))
        engine.handle(.shutdown)

        #expect(await eventually { log.isFinished })
        #expect(log.events == ["paused", "ready", "paused", "ended"])
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
}
