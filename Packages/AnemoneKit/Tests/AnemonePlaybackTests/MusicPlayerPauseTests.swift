import AnemoneJellyfin
@testable import AnemonePlayback
import Testing

/// Pausing before a song has started, and moving between songs while paused.
extension MusicPlayerTests {
    @Test func `a song paused while it loads stays paused once it's ready`() async {
        let player = player()
        player.play(songs("a"))
        _ = await eventually { engines.made.count == 1 && engine?.loads.isEmpty == false }

        player.pause()
        engine?.send(.ready)
        #expect(await eventually { player.songEngine?.isReady == true })

        #expect(player.status == .paused)
        #expect(engine?.isPlaying == false)
        #expect(!log.events.contains { $0.hasPrefix("started") })

        player.resume()
        #expect(player.status == .playing)
        #expect(engine?.isPlaying == true)
        #expect(await eventually { log.events.contains { $0.hasPrefix("started") } })
        player.stop()
    }

    @Test func `a song paused and resumed before its controller exists plays once ready`() async {
        let player = player()
        player.play(songs("a"))

        player.pause()
        #expect(player.status == .paused)
        player.resume()
        #expect(player.status == .loading)

        await startSong(1, in: player)
        #expect(engine?.isPlaying == true)
        player.stop()
    }

    @Test func `an instant mix paused while it loads starts paused`() async throws {
        let gate = LoadGate()
        let player = player()
        let loading = Task {
            try await player.play {
                await gate.wait()
                return [MusicItem.song("m1"), MusicItem.song("m2")]
            }
        }
        #expect(await eventually { gate.isReached })
        #expect(player.status == .loading)

        player.pause()
        gate.open()
        try await loading.value
        #expect(player.status == .paused)
        await expectHeldUntilResumed(player)
    }

    @Test(arguments: [
        (MusicSource.album("al1"), false),
        (MusicSource.library("lib"), true),
        (MusicSource.songs(library: "lib", sort: MusicSort(.random)), false),
    ])
    func `a source paused while it loads starts paused`(source: MusicSource, shuffled: Bool) async throws {
        library.songs = (0 ..< 3).map { MusicItem.song("s\($0)") }
        let gate = LoadGate()
        library.gate = gate
        let player = player()
        let loading = Task {
            try await player.play(source, shuffled: shuffled)
        }
        #expect(await eventually { gate.isReached })
        #expect(player.status == .loading)

        player.pause()
        gate.open()
        try await loading.value
        #expect(player.status == .paused)
        #expect(player.queue.entries.count == 3)
        await expectHeldUntilResumed(player)
    }

    @Test func `a load paused and resumed before it's in plays once it is`() async throws {
        let gate = LoadGate()
        let player = player()
        let loading = Task {
            try await player.play {
                await gate.wait()
                return [MusicItem.song("m1")]
            }
        }
        #expect(await eventually { gate.isReached })

        player.pause()
        player.resume()
        gate.open()
        try await loading.value
        #expect(player.status == .loading)
        await startSong(1, in: player)
        #expect(engine?.isPlaying == true)
        player.stop()
    }

    /// The first song loads, waits paused once it's ready, and plays when resumed.
    private func expectHeldUntilResumed(_ player: MusicPlayer) async {
        _ = await eventually { engines.made.count == 1 && engine?.loads.isEmpty == false }
        engine?.send(.ready)
        #expect(await eventually { player.songEngine?.isReady == true })
        #expect(player.status == .paused)
        #expect(engine?.isPlaying == false)
        #expect(!log.events.contains { $0.hasPrefix("started") })

        player.resume()
        #expect(player.status == .playing)
        #expect(engine?.isPlaying == true)
        player.stop()
    }

    @Test func `removing or skipping the song while paused moves on, still paused`() async {
        let center = FakeCenter()
        let player = player(nowPlaying: NowPlaying.Slot(center: center))
        player.play(songs("a", "b", "c"))
        await startSong(1, in: player)
        player.pause()

        player.removeEntry(at: 0)
        #expect(player.status == .paused)
        _ = await eventually { engines.made.count == 2 && engine?.loads.isEmpty == false }
        engine?.send(.ready)
        #expect(await eventually { player.songEngine?.isReady == true })
        #expect(player.current?.id == "b")
        #expect(player.status == .paused)
        #expect(engine?.isPlaying == false)
        // Now Playing shows the song waiting, paused.
        #expect(center.shown?.metadata.title == "Song b")
        #expect(center.shown?.isPlaying == false)

        player.next()
        _ = await eventually { engines.made.count == 3 && engine?.loads.isEmpty == false }
        engine?.send(.ready)
        #expect(await eventually { player.songEngine?.isReady == true })
        #expect(player.current?.id == "c")
        #expect(player.status == .paused)
        #expect(engine?.isPlaying == false)

        player.resume()
        #expect(player.status == .playing)
        #expect(engine?.isPlaying == true)
        player.stop()
    }

    @Test func `a song paused while it's tried again as a transcode stays paused`() async {
        let player = player()
        player.play(songs("a"))
        await startSong(1, in: player)

        engine?.send(.failed(PlayerError.streamFailed(underlying: nil)))
        player.pause()
        #expect(await eventually { engine?.loads.count == 2 })
        #expect(streams.received.last == SongStreams.Request(songID: "a", allowsDirect: false))
        engine?.send(.ready)
        #expect(await eventually { player.songEngine?.isReady == true })

        #expect(player.status == .paused)
        #expect(engine?.isPlaying == false)
        player.stop()
    }
}
