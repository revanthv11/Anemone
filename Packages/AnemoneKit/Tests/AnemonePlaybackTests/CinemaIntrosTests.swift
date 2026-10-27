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

    private func controller(
        _ entries: [PlaybackQueue.Entry],
        shuffles: Bool = false,
        streams: FakeStreams = FakeStreams(),
        intros: PlaybackRequest.Intros?,
    ) throws -> PlaybackController {
        try PlaybackController(
            request: PlaybackRequest(
                queue: #require(PlaybackQueue(entries: entries)),
                shuffles: shuffles,
                intros: intros,
            ),
            engine: engine,
            features: [log],
            positionInterval: .milliseconds(10),
            loadStream: streams.load,
        )
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
