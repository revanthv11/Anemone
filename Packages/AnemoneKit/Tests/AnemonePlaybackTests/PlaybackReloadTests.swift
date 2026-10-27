import AnemoneCore
import AnemoneJellyfin
@testable import AnemonePlayback
import Foundation
import JellyfinAPI
import Synchronization
import Testing

/// Reloading the entry for another stream.
@MainActor
struct PlaybackReloadTests {
    @Test func `a reload ends the session and plays on from the same position`() async {
        let engine = TrackEngine()
        let log = EventLog()
        let streams = FakeStreams()
        let playback = PlaybackController(
            request: PlaybackRequest(.item("m1", from: .seconds(5))),
            engine: engine,
            features: [log],
            loadStream: streams.load,
        )
        await playback.start()
        engine.send(.ready)
        _ = await eventually { log.events.contains { $0.hasPrefix("started") } }
        engine.currentTime = .seconds(30)

        playback.reload()

        #expect(await eventually { log.events.contains { $0.hasPrefix("reloaded") } })
        #expect(engine.loads.last?.position == .seconds(30))
        #expect(streams.received.last == .init(itemID: "m1", allowsDirect: true, mediaSourceID: "src-m1"))
        #expect(log.events.after("stopped 30.0 seconds") == ["reloaded m1 directPlay"])
    }

    @Test func `a reload while paused stays paused until playback resumes`() async {
        let engine = FakeEngine()
        let log = EventLog()
        let playback = PlaybackController(
            request: PlaybackRequest(.item("m1")),
            engine: engine,
            features: [log],
            loadStream: FakeStreams().load,
        )
        func ready(_ count: Int) async {
            _ = await eventually { engine.loads.count == count }
            engine.send(.ready)
            _ = await eventually {
                if case .playing = playback.state {
                    true
                } else {
                    false
                }
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        await playback.start()
        engine.send(.ready)
        _ = await eventually { log.events.contains { $0.hasPrefix("started") } }
        engine.currentTime = .seconds(30)
        engine.pause()
        #expect(await eventually { log.events.last == "paused 30.0 seconds" })

        playback.reload()
        await ready(2)
        #expect(!engine.isPlaying)
        #expect(log.events.after("stopped 30.0 seconds") == ["reloaded m1 directPlay"])
        // Again, both once it's ready and before it is.
        playback.reload()
        await ready(3)
        playback.reload()
        #expect(await eventually { engine.loads.count == 4 })
        playback.reload()
        await ready(5)
        #expect(!engine.isPlaying)
        #expect(engine.loads.map(\.position) == [nil] + Array(repeating: .seconds(30), count: 4))

        // Resuming gets it under way; a reload while playing plays on.
        engine.play()
        #expect(await eventually { log.events.last == "started 30.0 seconds" })
        playback.reload()
        await ready(6)
        #expect(engine.isPlaying)
    }

    @Test func `a reload before the stream is ready plays on from where it was to start`() async {
        let engine = FakeEngine()
        let playback = PlaybackController(
            request: PlaybackRequest(.item("m1", from: .seconds(300))),
            engine: engine,
            features: [],
            loadStream: FakeStreams().load,
        )
        await playback.start()

        // The engine says 0 until it's ready at the resume position, as AVPlayer does.
        playback.reload()
        #expect(await eventually { engine.loads.count == 2 })
        // And again, before the new stream is ready.
        playback.reload()
        #expect(await eventually { engine.loads.count == 3 })

        #expect(engine.loads.map(\.position) == [.seconds(300), .seconds(300), .seconds(300)])
    }

    @Test func `features have a say in each request for a stream`() async {
        let engine = FakeEngine()
        let picker = AudioPicker()
        let requests = StreamRequestLog()
        let playback = PlaybackController(
            request: PlaybackRequest(.item("m1")),
            engine: engine,
            features: [picker],
        ) { request in
            requests.append(request)
            return FakeStreams.stream(request.itemID, method: .directPlay)
        }
        await playback.start()
        picker.audioIndex = 2

        playback.reload()

        #expect(await eventually { requests.sent.count == 2 })
        #expect(requests.sent.map(\.audioStreamIndex) == [1, 2])
        #expect(requests.sent.map(\.mediaSourceID) == [nil, "src-m1"])
        #expect(requests.sent.first?.profile == engine.deviceProfile)
    }

    @Test func `a reload keeps the overlay's previews and takes the new stream`() async {
        let engine = FakeEngine()
        let fetches = Mutex(0)
        let details = PlaybackDetails { _, _ in
            fetches.withLock { $0 += 1 }
            return SeekPreviews()
        }
        let loads = Mutex(0)
        let playback = PlaybackController(
            request: PlaybackRequest(.item("m1")),
            engine: engine,
            features: [details],
        ) { request in
            // The reload gets a remux, to tell the streams apart.
            let count = loads.withLock { $0 += 1; return $0 }
            return FakeStreams.stream(request.itemID, method: count == 1 ? .directPlay : .directStream)
        }
        await playback.start()
        details.loadSeekPreviews()
        _ = await eventually { details.previews != nil }

        playback.reload()

        #expect(await eventually { details.stream?.method == .directStream })
        #expect(details.previews != nil)
        #expect(fetches.withLock(\.self) == 1)
    }

    @Test func `a reload keeps what Up Next and segment skipping did for the entry`() async throws {
        let engine = FakeEngine()
        let log = EventLog()
        let intro = MediaSegment(id: "intro", kind: .intro, start: .seconds(10), end: .seconds(40))
        let outro = MediaSegment(id: "outro", kind: .outro, start: .seconds(80), end: .seconds(100))
        let segments = SegmentSkipping(
            load: { _ in [intro, outro] },
            offerDuration: .milliseconds(300),
            behavior: { $0 == .intro ? .ask : .ignore },
        )
        let upNext = UpNext(
            settings: UpNext.Settings(
                autoplays: true,
                countdown: .seconds(100),
                timing: .duringCredits,
                passOutCount: 0,
                stillWatchingTimeout: .seconds(5),
                testCreditsStart: nil,
            ),
            second: .milliseconds(10),
        )
        let playback = try PlaybackController(
            request: PlaybackRequest(queue: #require(PlaybackQueue(entries: [.item("e1"), .item("e2")]))),
            engine: engine,
            features: [segments, log, upNext],
            positionInterval: .milliseconds(10),
            loadStream: FakeStreams().load,
        )
        func reload(_ count: Int) async {
            playback.reload()
            _ = await eventually { engine.loads.count == count }
            engine.send(.ready)
            _ = await eventually { log.events.count { $0.hasPrefix("started") } == count }
            try? await Task.sleep(for: .milliseconds(50))
        }
        await playback.start()
        engine.send(.ready)
        #expect(await eventually { !segments.segments.isEmpty })

        // The intro's skip button comes and goes, and doesn't come back after a reload.
        engine.currentTime = .seconds(12)
        #expect(await eventually { !playback.accessories.actions.isEmpty })
        #expect(await eventually { playback.accessories.actions.isEmpty })
        await reload(2)
        #expect(log.events.after("stopped 12.0 seconds").first == "reloaded e1 directPlay")
        #expect(playback.accessories.actions.isEmpty)

        // Up Next comes with the credits and is cancelled, and stays cancelled after a reload.
        engine.currentTime = .seconds(85)
        #expect(await eventually { playback.accessories.card?.id == UpNext.upNextCard })
        try #require(playback.accessories.card?.actions.first { $0.id == "upNext.cancel" }).perform()
        await reload(3)
        #expect(engine.loads.last?.position == .seconds(85))
        #expect(playback.accessories.card == nil)
        await playback.stop()
    }
}

/// A reload's requests: a retry after a reloaded stream fails, and reloads that come while the
/// server is asked.
@MainActor
struct PlaybackReloadRequestTests {
    @Test func `a transcode retry after a reloaded stream fails is still a reload`() async {
        let engine = FakeEngine()
        let log = EventLog()
        let streams = FakeStreams()
        let intro = MediaSegment(id: "intro", kind: .intro, start: .seconds(10), end: .seconds(40))
        let segments = SegmentSkipping(
            load: { _ in [intro] },
            offerDuration: .milliseconds(300),
            behavior: { $0 == .intro ? .ask : .ignore },
        )
        let playback = PlaybackController(
            request: PlaybackRequest(.item("m1")),
            engine: engine,
            features: [segments, log],
            positionInterval: .milliseconds(10),
            loadStream: streams.load,
        )
        func ready(_ count: Int) async {
            _ = await eventually { engine.loads.count == count }
            engine.send(.ready)
            _ = await eventually { log.events.count { $0.hasPrefix("started") } == count }
        }
        await playback.start()
        await ready(1)
        #expect(await eventually { !segments.segments.isEmpty })
        // The intro's skip button comes and goes.
        engine.currentTime = .seconds(12)
        #expect(await eventually { !playback.accessories.actions.isEmpty })
        #expect(await eventually { playback.accessories.actions.isEmpty })

        playback.reload()
        await ready(2)
        engine.send(.failed(PlayerError.streamFailed(underlying: nil)))
        await ready(3)
        try? await Task.sleep(for: .milliseconds(100))

        #expect(streams.received.map(\.allowsDirect) == [true, true, false])
        #expect(log.events.after("failed") == ["stopped 12.0 seconds", "reloaded m1 transcode"])
        // Still the same entry, so the skip button doesn't come back.
        #expect(playback.accessories.actions.isEmpty)
        await playback.stop()
    }

    @Test func `quick picks while the server is asked come to one more request, for the last`() async {
        let engine = FakeEngine()
        let log = EventLog()
        let picker = AudioPicker()
        let requests = StreamRequestLog()
        let asking = Mutex(0)
        let mostAtOnce = Mutex(0)
        let (answers, answer) = AsyncStream.makeStream(of: Void.self)
        let playback = PlaybackController(
            request: PlaybackRequest(.item("m1")),
            engine: engine,
            features: [picker, log],
        ) { request in
            requests.append(request)
            let count = asking.withLock { $0 += 1; return $0 }
            mostAtOnce.withLock { $0 = max($0, count) }
            // The first reload's answer waits for the test.
            if request.audioStreamIndex == 3 {
                for await _ in answers {
                    break
                }
            }
            asking.withLock { $0 -= 1 }
            return FakeStreams.stream(request.itemID, method: .directPlay)
        }
        await playback.start()
        engine.send(.ready)
        _ = await eventually { log.events.contains { $0.hasPrefix("started") } }

        // Two picks before the reload asks the server: it asks for the second.
        picker.audioIndex = 2
        playback.reload()
        picker.audioIndex = 3
        playback.reload()
        #expect(await eventually { requests.sent.count == 2 })
        // Two more, a moment apart, while it's asked.
        picker.audioIndex = 4
        playback.reload()
        try? await Task.sleep(for: .milliseconds(50))
        picker.audioIndex = 5
        playback.reload()
        try? await Task.sleep(for: .milliseconds(50))
        answer.yield()

        #expect(await eventually { engine.loads.count == 2 })
        try? await Task.sleep(for: .milliseconds(50))
        #expect(requests.sent.map(\.audioStreamIndex) == [1, 3, 5])
        #expect(mostAtOnce.withLock(\.self) == 1)
        #expect(engine.loads.count == 2)
        #expect(log.events.count { $0.hasPrefix("stopped") } == 1)
        #expect(log.events.count { $0.hasPrefix("reloaded") } == 1)
    }
}

/// A feature that asks for an audio track.
@MainActor
private final class AudioPicker: PlaybackFeature {
    var audioIndex = 1

    func handle(_: PlaybackEvent, in _: PlaybackController) async {}

    func prepare(_ request: inout StreamRequest) async {
        request.audioStreamIndex = audioIndex
    }
}
