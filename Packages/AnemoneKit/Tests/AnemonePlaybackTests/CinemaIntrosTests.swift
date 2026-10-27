import AnemoneCore
import AnemoneJellyfin
@testable import AnemonePlayback
import Foundation
import Synchronization
import Testing

/// Cinema-mode intros: found before the first entry loads, played straight into it.
@MainActor
struct CinemaIntrosTests {
    private let engine = FakeEngine()
    private let log = EventLog()

    /// A player whose server won't offer a stream for the items in `failing`.
    private func controller(
        _ entries: [PlaybackQueue.Entry],
        shuffles: Bool = false,
        streams: FakeStreams = FakeStreams(),
        failing: Set<MediaItem.ID> = [],
        features: [any PlaybackFeature] = [],
        intros: PlaybackRequest.Intros?,
    ) throws -> PlaybackController {
        let load = streams.load
        return try PlaybackController(
            request: PlaybackRequest(
                queue: #require(PlaybackQueue(entries: entries)),
                shuffles: shuffles,
                intros: intros,
            ),
            engine: engine,
            features: features + [log],
            positionInterval: .milliseconds(10),
        ) { itemID, allowsDirect, mediaSourceID in
            let stream = try await load(itemID, allowsDirect, mediaSourceID)
            if failing.contains(itemID) {
                throw PlaybackError.nothingToPlay
            }
            return stream
        }
    }

    private static let twoIntros: PlaybackRequest.Intros = { _ in
        CinemaIntros.entries(for: [
            MediaItem(id: "i1", name: "Pre-roll One", kind: .video),
            MediaItem(id: "i2", name: "Pre-roll Two", kind: .video),
        ])
    }

    @Test func `intros play before the movie, then the movie from where it was asked to start`() async throws {
        let streams = FakeStreams()
        let playback = try controller([.item("m1")], streams: streams, intros: Self.twoIntros)

        await playback.start()

        #expect(playback.queue.entries.map(\.itemID) == ["i1", "i2", "m1"])
        #expect(playback.queue.entries.map(\.isIntro) == [true, true, false])
        #expect(playback.queue.current.itemID == "i1")
        #expect(streams.received.map(\.itemID) == ["i1"])
        #expect(engine.loads.first?.metadata.title == "Pre-roll One")
    }

    @Test func `an intro that ends plays the next entry at once, without Up Next hearing it end`() async throws {
        let streams = FakeStreams()
        let playback = try controller([.item("m1")], streams: streams, intros: Self.twoIntros)
        await playback.start()
        engine.send(.ready)
        #expect(await eventually { log.events.contains { $0.hasPrefix("started") } })
        engine.currentTime = .seconds(6)

        engine.send(.ended)

        #expect(await eventually { engine.loads.count == 2 })
        #expect(playback.queue.current.itemID == "i2")
        #expect(!log.events.contains("ended"))
        #expect(log.events.suffix(2) == ["stopped 6.0 seconds", "loaded i2 directPlay"])
        #expect(!playback.hasEnded)

        engine.send(.ready)
        #expect(await eventually { log.events.last?.hasPrefix("started") == true })
        engine.send(.ended)

        #expect(await eventually { playback.queue.current.itemID == "m1" && engine.loads.count == 3 })
        #expect(streams.received.map(\.itemID) == ["i1", "i2", "m1"])
    }

    @Test func `the movie still ends the queue as before`() async throws {
        let playback = try controller([.item("m1")], intros: Self.twoIntros)
        await playback.start()
        playback.play(entryAt: 2)
        #expect(await eventually { playback.queue.current.itemID == "m1" && engine.loads.count == 2 })
        engine.send(.ready)
        #expect(await eventually { log.events.last?.hasPrefix("started") == true })

        engine.send(.ended)

        #expect(await eventually { playback.hasEnded })
        #expect(log.events.contains("ended"))
    }

    @Test func `intros are found for the entry that plays first, after shuffling`() async throws {
        let asked = Mutex<[MediaItem.ID]>([])
        let playback = try controller([.item("e1"), .item("e2"), .item("e3")], shuffles: true) { first in
            asked.withLock { $0.append(first.itemID) }
            return []
        }

        await playback.start()

        #expect(asked.withLock(\.self) == [playback.queue.entries[0].itemID])
        #expect(playback.queue.entries.count == 3)
    }

    @Test func `when intros can't be found, the queue plays as it is`() async throws {
        let playback = try controller([.item("m1")]) { _ in throw PlaybackError.nothingToPlay }

        await playback.start()

        #expect(playback.queue.entries.map(\.itemID) == ["m1"])
        #expect(engine.loads.count == 1)
    }

    // MARK: Intros that won't play

    @Test func `an intro the server won't offer is passed over, as is the next, and the movie plays`() async throws {
        let streams = FakeStreams()
        let playback = try controller([.item("m1")], streams: streams, failing: ["i1", "i2"], intros: Self.twoIntros)

        await playback.start()

        #expect(await eventually { engine.loads.count == 1 })
        #expect(playback.queue.current.itemID == "m1")
        #expect(engine.loads.first?.url == FakeStreams.stream("m1", method: .directPlay).url)
        #expect(streams.received.map(\.itemID) == ["i1", "i2", "m1"])
        // Nothing loaded for the intros, so features hear of the movie alone.
        #expect(log.events == ["loaded m1 directPlay"])
        #expect(!playback.isShowingError)

        engine.send(.ready)
        #expect(await eventually { playback.isPlaying })
    }

    @Test func `an intro that fails as it plays, and again as a transcode, is passed over`() async throws {
        let streams = FakeStreams()
        let playback = try controller([.item("m1")], streams: streams, intros: Self.twoIntros)
        await playback.start()
        engine.send(.ready)
        #expect(await eventually { log.events.contains { $0.hasPrefix("started") } })

        engine.send(.failed(PlayerError.streamFailed(underlying: nil)))
        // Tried again as a transcode first, like any entry.
        #expect(await eventually { engine.loads.count == 2 })
        let retry = FakeStreams.Request(itemID: "i1", allowsDirect: false, mediaSourceID: "src-i1")
        #expect(streams.received.last == retry)
        engine.send(.failed(PlayerError.streamFailed(underlying: nil)))

        #expect(await eventually { playback.queue.current.itemID == "i2" && engine.loads.count == 3 })
        #expect(!playback.isShowingError)
        #expect(log.events.suffix(2) == ["stopped 0.0 seconds", "loaded i2 directPlay"])
    }

    @Test func `the movie the intros lead into still shows its error`() async throws {
        let playback = try controller([.item("m1")], failing: ["m1"], intros: Self.twoIntros)
        await playback.start()

        playback.play(entryAt: 2)

        #expect(await eventually { playback.isShowingError })
        #expect(playback.queue.current.itemID == "m1")
    }

    // MARK: What counts entries passes over intros

    @Test func `next, previous and the counts pass over intros`() throws {
        var queue = try #require(PlaybackQueue(entries: [.item("m1"), .item("m2")]))
        queue.insertBeforeCurrent(CinemaIntros.entries(for: [
            MediaItem(id: "i1", name: "Pre-roll One", kind: .video),
            MediaItem(id: "i2", name: "Pre-roll Two", kind: .video),
        ]))

        #expect(queue.current.itemID == "i1")
        // The player goes on to the second intro; Next and Up Next to the movie.
        #expect(queue.afterIntroIndex == 1)
        #expect(queue.next?.itemID == "m1")
        #expect(queue.nextIndex == 2)
        #expect(queue.previousIndex == nil)
        #expect(queue.upcoming.map(\.index) == [2, 3])
        #expect(queue.countWithoutIntros == 2)
        #expect(queue.indexWithoutIntros == 0)

        queue.currentIndex = 2
        #expect(queue.afterIntroIndex == nil)
        #expect(queue.previousIndex == nil)
        #expect(queue.next?.itemID == "m2")
        #expect(queue.indexWithoutIntros == 0)

        queue.currentIndex = 3
        #expect(queue.previousIndex == 2)
        #expect(queue.next == nil)
        #expect(queue.upcoming.isEmpty)
        #expect(queue.indexWithoutIntros == 1)
    }

    @Test func `intros bring no Up Next, and aren't counted in its note about skipped items`() async throws {
        let upNext = UpNext(
            settings: UpNext.Settings(countdown: .seconds(100), testCreditsStart: .seconds(5)),
            second: .milliseconds(10),
        )
        var queue = try #require(PlaybackQueue(entries: [.item("m1"), .item("m2")]))
        queue.overLimitCount = 3
        let playback = PlaybackController(
            request: PlaybackRequest(queue: queue, intros: Self.twoIntros),
            engine: engine,
            features: [log, upNext],
            positionInterval: .milliseconds(10),
            loadStream: FakeStreams().load,
        )
        await playback.start()
        engine.send(.ready)
        #expect(await eventually { log.events.contains { $0.hasPrefix("started") } })

        // Past where the credits start, during the first intro.
        engine.currentTime = .seconds(6)
        try await Task.sleep(for: .milliseconds(50))
        #expect(playback.accessories.card == nil)

        // The note waits for the movie.
        playback.play(entryAt: 2)
        #expect(await eventually { engine.loads.count == 2 })
        engine.currentTime = .zero
        engine.send(.ready)
        #expect(await eventually { playback.accessories.card?.id == UpNext.skippedCard })
        #expect(playback.accessories.card?.title == "Playing 2 of 5 items")
    }

    @Test func `intros don't count toward pass-out protection`() async throws {
        let upNext = UpNext(
            settings: UpNext.Settings(countdown: .zero, passOutCount: 1),
            second: .milliseconds(10),
        )
        let playback = try controller([.item("m1"), .item("m2"), .item("m3")], features: [upNext]) { _ in
            CinemaIntros.entries(for: [MediaItem(id: "i1", name: "Pre-roll One", kind: .video)])
        }
        await playback.start()

        // The intro plays straight into the first movie, which isn't an autoplay.
        engine.send(.ready)
        engine.send(.ended)
        #expect(await eventually { playback.queue.current.itemID == "m1" && engine.loads.count == 2 })
        #expect(upNext.autoplaysWithoutInput == 0)

        // So the first movie's end still plays the next on its own.
        engine.send(.ready)
        engine.send(.ended)
        #expect(await eventually { playback.queue.current.itemID == "m2" && engine.loads.count == 3 })
        #expect(upNext.autoplaysWithoutInput == 1)
        #expect(playback.accessories.card == nil)
    }

    @Test func `intros aren't counted in Now Playing, and Next during one plays the movie`() async throws {
        let center = FakeCenter()
        let nowPlaying = NowPlaying(center: center) { _ in nil }
        nowPlaying.usesSystemPlayer = false
        let streams = FakeStreams()
        let playback = try controller(
            [.item("m1"), .item("m2")],
            streams: streams,
            features: [nowPlaying],
            intros: Self.twoIntros,
        )
        await playback.start()

        #expect(nowPlaying.info?.queueIndex == 0)
        #expect(nowPlaying.info?.queueCount == 2)
        #expect(center.commands.contains(.nextTrack))

        #expect(center.send(.next))
        #expect(await eventually { streams.received.map(\.itemID) == ["i1", "m1"] })
        #expect(await eventually { nowPlaying.info?.metadata.title == "Title m1" })
        #expect(nowPlaying.info?.queueIndex == 0)

        // Early in the movie, Previous starts it again rather than going back to an intro.
        engine.currentTime = .seconds(1)
        #expect(center.send(.previous))
        try await Task.sleep(for: .milliseconds(50))
        #expect(streams.received.map(\.itemID) == ["i1", "m1"])
        #expect(engine.currentTime == .zero)
        await playback.stop()
    }

    @Test func `cinema mode looks for intros only when starting from the beginning`() async throws {
        let session = JellyfinSession(
            serverURL: URL(filePath: "/nowhere"),
            userID: "u1",
            accessToken: "tok",
            identity: ClientIdentity(deviceName: "Test TV", deviceID: "device-1", appVersion: "0.1.0"),
        )
        let finder = try #require(CinemaIntros.finder(on: session, isOn: true))

        // Resuming asks the server nothing, so the unreachable server doesn't matter.
        let resumed = try await finder(.item("m1", from: .seconds(600)))

        #expect(resumed.isEmpty)
        #expect(CinemaIntros.finder(on: session, isOn: false) == nil)
        #expect(Preferences.cinemaMode.defaultValue)
    }
}

private extension PlaybackController {
    var isShowingError: Bool {
        if case .failed = state {
            true
        } else {
            false
        }
    }

    var isPlaying: Bool {
        if case .playing = state {
            true
        } else {
            false
        }
    }
}
