import AnemoneJellyfin
@testable import AnemonePlayback
import Foundation
import Testing

/// Music in the system's Now Playing, through the same `NowPlaying` as video: one for the player,
/// which every song's controller shares, and the sidebar's Now Playing entry.
extension MusicPlayerTests {
    func album(_ ids: String...) -> [MusicItem] {
        ids.map { id in
            var song = MusicItem.song(id)
            song.albumName = "Promo"
            song.artists = ["Binaerpilot"]
            return song
        }
    }

    @Test func `each song shows in Now Playing as music, at its place in the player's queue`() async throws {
        let center = FakeCenter()
        let player = player(nowPlaying: NowPlaying.Slot(center: center))
        player.play(album("a", "b"))
        await startSong(1, in: player)

        let shown = try #require(center.shown)
        #expect(shown.metadata.title == "Song a")
        #expect(shown.metadata.subtitle == "Binaerpilot")
        #expect(shown.metadata.artworkURL == URL(filePath: "/covers/Promo.jpg"))
        #expect(shown.album == "Promo")
        #expect(shown.isMusic)
        #expect(shown.queueIndex == 0)
        #expect(shown.queueCount == 2)
        #expect(await eventually { center.shown?.isPlaying == true })
        // The track buttons rather than skips.
        #expect(center.commands == [.play, .pause, .togglePlayPause, .changePosition, .previousTrack, .nextTrack])

        player.next()
        await startSong(2, in: player)
        #expect(center.shown?.metadata.title == "Song b")
        #expect(center.shown?.queueIndex == 1)
        #expect(!center.commands.contains(.nextTrack))
        // Repeating the queue gives the last song a next.
        player.cycleRepeatMode()
        #expect(await eventually { center.commands.contains(.nextTrack) })
        player.stop()
    }

    @Test func `the remote's commands go to the music player`() async {
        let center = FakeCenter()
        let player = player(nowPlaying: NowPlaying.Slot(center: center))
        player.play(album("a", "b"))
        await startSong(1, in: player)

        #expect(center.send(.pause))
        #expect(player.status == .paused)
        #expect(engine?.isPlaying == false)
        #expect(center.send(.togglePlayPause))
        #expect(player.status == .playing)
        #expect(engine?.isPlaying == true)
        #expect(center.send(.seek(.seconds(42))))
        #expect(center.shown?.position == .seconds(42))
        #expect(await eventually { engine?.currentTime == .seconds(42) })

        #expect(center.send(.next))
        await startSong(2, in: player)
        #expect(player.current?.id == "b")
        #expect(center.send(.next) == false)
        // Early in a song, Previous goes back a song.
        #expect(center.send(.previous))
        await startSong(3, in: player)
        #expect(player.current?.id == "a")
        player.stop()
    }

    @Test func `the music stays in Now Playing between songs and at the end of the queue, and Stop clears it`() async {
        let center = FakeCenter()
        let player = player(nowPlaying: NowPlaying.Slot(center: center))
        player.play(album("a", "b"))
        await startSong(1, in: player)

        engine?.send(.ended)
        await startSong(2, in: player)
        #expect(!center.published.contains { $0 == nil })
        #expect(center.isHandling)

        engine?.send(.ended)
        #expect(await eventually { player.status == .ended })
        #expect(await eventually { log.events.count { $0.hasPrefix("stopped") } == 2 })
        #expect(center.shown?.metadata.title == "Song b")
        #expect(center.shown?.isPlaying == false)
        #expect(center.shown?.position == .seconds(100))
        #expect(center.isHandling)

        // Play starts the queue again, as Play on the page does.
        #expect(center.send(.play))
        await startSong(3, in: player)
        #expect(player.current?.id == "a")

        player.stop()
        #expect(center.published.last == .some(nil))
        #expect(!center.isHandling)
        // The song's session ending afterwards changes nothing.
        let cleared = center.published.count
        #expect(await eventually { log.events.count { $0.hasPrefix("stopped") } == 3 })
        #expect(center.published.count == cleared)
    }

    @Test func `a new queue leaves the last song in Now Playing until its first song shows`() async throws {
        let center = FakeCenter()
        let player = player(nowPlaying: NowPlaying.Slot(center: center))
        player.play(album("a"))
        await startSong(1, in: player)
        let gate = LoadGate()
        library.gate = gate
        library.songs = album("x", "y")

        let starting = Task { try await player.play(.album("al2")) }

        // The last song's session has ended, and the new queue is still being fetched.
        #expect(await eventually { gate.isReached })
        #expect(await eventually { log.events.contains { $0.hasPrefix("stopped") } })
        #expect(!center.published.contains { $0 == nil })
        #expect(center.shown?.metadata.title == "Song a")
        #expect(center.isHandling)

        gate.open()
        try await starting.value
        await startSong(2, in: player)
        #expect(center.shown?.metadata.title == "Song x")
        #expect(center.shown?.queueCount == 2)
        #expect(!center.published.contains { $0 == nil })
        player.stop()
        #expect(center.published.last == .some(nil))
    }

    @Test func `a new queue that can't be fetched clears Now Playing`() async {
        let center = FakeCenter()
        let player = player(nowPlaying: NowPlaying.Slot(center: center))
        player.play(album("a"))
        await startSong(1, in: player)
        library.failsFrom = 0

        await #expect(throws: PlaybackError.self) { try await player.play(.album("al2")) }

        #expect(player.status == .idle)
        #expect(center.published.last == .some(nil))
        #expect(!center.isHandling)
    }

    @Test func `at the end of the queue, Next and the queue's place follow changes to the queue`() async {
        let center = FakeCenter()
        let player = player(nowPlaying: NowPlaying.Slot(center: center))
        player.play(album("a", "b", "c"))
        await startSong(1, in: player)
        player.playEntry(at: 2)
        await startSong(2, in: player)
        engine?.send(.ended)
        #expect(await eventually { player.status == .ended })
        #expect(await eventually { log.events.count { $0.hasPrefix("stopped") } == 2 })
        #expect(!center.commands.contains(.nextTrack))

        // No song plays to update Now Playing, so each change shows at once.
        player.cycleRepeatMode()
        #expect(center.commands.contains(.nextTrack))
        player.cycleRepeatMode()
        #expect(!center.commands.contains(.nextTrack))
        player.cycleRepeatMode()

        player.addToQueue(album("d"))
        #expect(center.shown?.queueCount == 4)
        #expect(center.commands.contains(.nextTrack))
        player.removeEntry(at: 3)
        #expect(center.shown?.queueCount == 3)
        #expect(!center.commands.contains(.nextTrack))

        // Shuffled, a move keeps the song's own place for when shuffle is off again.
        player.toggleShuffle()
        player.moveEntry(from: 2, to: 0)
        #expect(center.shown?.queueIndex == 0)
        #expect(center.commands.contains(.nextTrack))
        player.toggleShuffle()
        #expect(center.shown?.queueIndex == 2)
        #expect(!center.commands.contains(.nextTrack))
        #expect(center.shown?.metadata.title == "Song c")
        player.stop()
    }

    @Test func `the system shows a seek's position while the engine gets there`() async {
        let gate = LoadGate()
        let center = FakeCenter()
        var made: [SeekHoldingEngine] = []
        let player = MusicPlayer(
            nowPlaying: NowPlaying.Slot(center: center),
            stopTimeout: .milliseconds(200),
            tickInterval: .milliseconds(5),
            makeEngine: {
                let engine = SeekHoldingEngine(gate: gate)
                made.append(engine)
                return engine
            },
            makeFeatures: { [] },
            loadSongs: library.load,
            loadStream: streams.load,
        )
        player.play(album("a"))
        _ = await eventually { made.count == 1 && made.last?.base.loads.isEmpty == false }
        made.last?.base.send(.ready)
        #expect(await eventually { player.status == .playing })
        made.last?.base.currentTime = .seconds(10)

        // From the Now Playing page, not the remote: the system shows it at once too.
        let beforeSeek = center.published.count
        player.seek(to: .seconds(42))
        #expect(center.shown?.position == .seconds(42))
        #expect(await eventually { gate.isReached })

        // The song's events tell the engine's old time until the seek lands.
        player.pause()
        #expect(await eventually { center.shown?.isPlaying == false })
        #expect(center.shown?.position == .seconds(42))
        #expect(center.published.dropFirst(beforeSeek).allSatisfy { $0?.position == .seconds(42) })

        gate.open()
        #expect(await eventually { !player.isSeeking })
        player.stop()
    }

    @Test func `a song the server can't send shows in Now Playing, not the one before`() async {
        let center = FakeCenter()
        let player = player(nowPlaying: NowPlaying.Slot(center: center))
        player.play(album("a", "b"))
        await startSong(1, in: player)

        streams.fail = true
        player.next()

        #expect(await eventually { player.status == .failed })
        #expect(await eventually { center.shown?.metadata.title == "Song b" })
        #expect(center.shown?.isPlaying == false)
        #expect(center.isHandling)
        player.stop()
    }

    @Test func `a video that stops the music keeps its own Now Playing`() async {
        let center = FakeCenter()
        let slot = NowPlaying.Slot(center: center)
        let player = player(nowPlaying: slot)
        player.play(album("a"))
        await startSong(1, in: player)

        let video = PlaybackController(
            request: PlaybackRequest(.item("m1")),
            engine: FakeEngine(),
            features: [MusicStopping(), NowPlaying(slot: slot) { _ in nil }],
            loadStream: FakeStreams().load,
        )
        await video.start()
        #expect(player.status == .idle)
        #expect(center.shown?.metadata.title == "Title m1")

        // The song's session ends after the video has taken Now Playing.
        #expect(await eventually { log.events.contains { $0.hasPrefix("stopped") } })
        #expect(center.shown?.metadata.title == "Title m1")
        #expect(center.isHandling)
        #expect(center.commands.contains(.skipForward))
        await video.stop()
    }

    @Test func `the sidebar offers Now Playing while music plays, until it has been still a while`() async {
        let player = player(offerTimeout: .milliseconds(100))
        #expect(!player.offersNowPlaying)

        player.play(songs("a"))
        #expect(player.offersNowPlaying)
        await startSong(1, in: player)
        player.pause()
        #expect(player.offersNowPlaying)
        #expect(await eventually { !player.offersNowPlaying })

        player.resume()
        #expect(player.offersNowPlaying)
        player.stop()
        #expect(!player.offersNowPlaying)
    }
}
