import AnemoneJellyfin
@testable import AnemonePlayback
import Testing

/// Queues from a source, and changing the queue.
extension MusicPlayerTests {
    @Test func `a source plays its first page at once and pages in the rest`() async throws {
        library.songs = (0 ..< 250).map { MusicItem.song("s\($0)") }
        let player = player()

        try await player.play(.album("al1"))
        await startSong(1, in: player)

        #expect(player.queue.entries.count == 250)
        #expect(library.received.map(\.startIndex) == [0, 100, 200])
        #expect(library.received.allSatisfy { !$0.shuffled && $0.limit == 100 })
        #expect(player.current?.id == "s0")
        player.stop()
    }

    @Test func `shuffling a library asks the server for one random page`() async throws {
        library.songs = (0 ..< 50).map { MusicItem.song("s\($0)") }
        let player = player()

        try await player.play(.library("lib"), shuffled: true)
        await startSong(1, in: player)

        #expect(library.received.count == 1)
        #expect(library.received.first?.shuffled == true)
        #expect(library.received.first?.limit == 500)
        #expect(player.queue.isShuffled)
        #expect(player.queue.entries.count == 50)
        player.stop()
    }

    @Test func `a new queue stops the old one at once, and stops the player if it can't load`() async {
        let player = player()
        player.play(songs("a"))
        await startSong(1, in: player)
        let first = engine

        await #expect(throws: PlaybackError.nothingToPlay) {
            try await player.play { throw PlaybackError.nothingToPlay }
        }

        #expect(first?.isStopped == true)
        #expect(player.status == .idle)
        #expect(!player.hasQueue)
    }

    @Test func `an instant mix plays the songs it loads`() async throws {
        let player = player()

        try await player.play { [MusicItem.song("m1"), MusicItem.song("m2")] }
        await startSong(1, in: player)

        #expect(player.queue.entries.map(\.song.id) == ["m1", "m2"])
        player.stop()
    }

    @Test func `play next and add to queue start playing when nothing is queued`() async {
        let player = player()

        player.addToQueue(songs("a"))
        await startSong(1, in: player)
        player.playNext(songs("b"))
        player.addToQueue(songs("c"))

        #expect(player.queue.entries.map(\.song.id) == ["a", "b", "c"])
        player.stop()
    }
}
