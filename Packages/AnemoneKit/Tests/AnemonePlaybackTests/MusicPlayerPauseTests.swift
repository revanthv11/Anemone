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

    @Test func `removing or skipping the song while paused moves on, still paused`() async {
        let remote = RecordingRemote()
        let player = player(remote: remote)
        player.play(songs("a", "b", "c"))
        await startSong(1, in: player)
        player.pause()

        player.removeEntry(at: 0)
        #expect(player.status == .paused)
        #expect(remote.statuses.last == .paused)
        _ = await eventually { engines.made.count == 2 && engine?.loads.isEmpty == false }
        engine?.send(.ready)
        #expect(await eventually { player.songEngine?.isReady == true })
        #expect(player.current?.id == "b")
        #expect(player.status == .paused)
        #expect(engine?.isPlaying == false)

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
