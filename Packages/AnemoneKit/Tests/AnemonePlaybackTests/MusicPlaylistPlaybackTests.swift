import AnemoneJellyfin
@testable import AnemonePlayback
import Testing

/// Play on a playlist page whose entries haven't loaded: the player pages the playlist in itself
/// and goes by its first page.
extension MusicPlayerTests {
    @Test func `a playlist not listed yet plays from its pages when its first page is songs`() async throws {
        library.songs = (0 ..< 250).map { MusicItem.song("s\($0)") }
        let player = player()

        let isMusic = try await player.play(playlist: "pl1")
        await startSong(1, in: player)

        #expect(isMusic)
        #expect(await eventually { player.queue.entries.count == 250 })
        #expect(player.current?.id == "s0")
        // The paged playlist, a page at a time, rather than every entry in one request.
        #expect(library.received.map(\.source) == Array(repeating: .playlist("pl1"), count: 3))
        #expect(library.received.map(\.startIndex) == [0, 100, 200])
        #expect(library.received.allSatisfy { $0.limit == 100 })
        player.stop()
    }

    @Test func `a playlist not listed yet takes no more than a queue's limit`() async throws {
        library.songs = (0 ..< 1200).map { MusicItem.song("s\($0)") }
        let player = player()

        _ = try await player.play(playlist: "pl1")
        await startSong(1, in: player)

        #expect(await eventually { library.received.count == 10 })
        #expect(await eventually { player.queue.entries.count == MusicPlayer.queueLimit })
        #expect(library.received.map(\.startIndex) == Array(stride(from: 0, to: 1000, by: 100)))
        player.stop()
    }

    @Test func `a shuffled playlist not listed yet is fetched first, up to a queue's limit`() async throws {
        library.songs = (0 ..< 1200).map { MusicItem.song("s\($0)") }
        let player = player()

        let isMusic = try await player.play(playlist: "pl1", shuffled: true)
        await startSong(1, in: player)

        #expect(isMusic)
        #expect(library.received.map(\.startIndex) == [0, 100, 600])
        #expect(library.received.map(\.limit) == [100, 500, 400])
        #expect(player.queue.isShuffled)
        #expect(player.queue.entries.count == MusicPlayer.queueLimit)
        #expect(Set(player.queue.entries.map(\.song.id)).count == MusicPlayer.queueLimit)
        player.stop()
    }

    @Test func `a playlist not listed yet with anything but songs first is the video player's`() async throws {
        library.songs = (0 ..< 10).map { MusicItem.song("s\($0)") }
        library.notSongs = [4]
        let player = player()
        player.play(songs("a"))
        await startSong(1, in: player)
        let first = engine

        let isMusic = try await player.play(playlist: "pl1")

        #expect(!isMusic)
        #expect(await eventually { first?.isStopped == true })
        #expect(player.status == .idle)
        #expect(!player.hasQueue)
        #expect(library.received.count == 1)
    }

    @Test func `an empty playlist not listed yet is the video player's`() async throws {
        let player = player()

        let isMusic = try await player.play(playlist: "pl1")

        #expect(!isMusic)
        #expect(player.status == .idle)
    }

    @Test func `a song that can't be read leaves a playlist not listed yet as music`() async throws {
        library.songs = (0 ..< 10).map { MusicItem.song("s\($0)") }
        library.unreadable = [4]
        let player = player()

        let isMusic = try await player.play(playlist: "pl1")
        await startSong(1, in: player)

        #expect(isMusic)
        #expect(player.queue.entries.map(\.song.id) == (0 ..< 10).filter { $0 != 4 }.map { "s\($0)" })
        player.stop()
    }

    @Test func `play on a playlist not listed yet stops the music at once, and a newer queue wins`() async throws {
        library.songs = (0 ..< 10).map { MusicItem.song("s\($0)") }
        let player = player()
        player.play(songs("a"))
        await startSong(1, in: player)
        let first = engine
        let gate = LoadGate()
        library.gate = gate

        let playlist = Task { try await player.play(playlist: "pl1") }
        #expect(await eventually { gate.isReached })
        // What was playing stopped before the playlist's first page came in.
        #expect(await eventually { first?.isStopped == true })
        #expect(player.status == .loading)
        player.play(songs("b"))
        gate.open()

        // The playlist's page came in after a newer queue started, so it's dropped.
        #expect(try await playlist.value)
        await startSong(2, in: player)
        #expect(player.queue.entries.map(\.song.id) == ["b"])
        player.stop()
    }

    @Test func `a playlist not listed yet whose first page fails stops the player and says why`() async {
        library.songs = (0 ..< 10).map { MusicItem.song("s\($0)") }
        library.failsFrom = 0
        let player = player()

        await #expect(throws: PlaybackError.nothingToPlay) {
            try await player.play(playlist: "pl1")
        }

        #expect(player.status == .idle)
        #expect(!player.hasQueue)
    }
}
