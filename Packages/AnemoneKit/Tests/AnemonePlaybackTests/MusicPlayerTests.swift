import AnemoneJellyfin
@testable import AnemonePlayback
import Foundation
import Synchronization
import Testing

/// Playing a queue of songs through fake engines, one per song, as `MusicService` plays them.
@MainActor
@Suite(.serialized)
struct MusicPlayerTests {
    let log = EventLog()
    let streams = SongStreams()
    let library = FakeLibrary()

    /// Every engine the player made, one per song.
    final class Engines {
        var made: [FakeEngine] = []
    }

    let engines = Engines()

    func player(remote: (any MusicRemote)? = nil) -> MusicPlayer {
        let engines = engines
        let log = log
        return MusicPlayer(
            remote: remote,
            stopTimeout: .milliseconds(200),
            tickInterval: .milliseconds(10),
            makeEngine: {
                let engine = FakeEngine()
                engines.made.append(engine)
                return engine
            },
            makeFeatures: { [log] },
            loadSongs: library.load,
            loadStream: streams.load,
        )
    }

    var engine: FakeEngine? {
        engines.made.last
    }

    /// Waits for the song's engine to load, then gets it playing.
    func startSong(_ count: Int, in player: MusicPlayer) async {
        _ = await eventually { engines.made.count == count && engine?.loads.isEmpty == false }
        engine?.send(.ready)
        _ = await eventually { player.status == .playing }
    }

    func songs(_ ids: String...) -> [MusicItem] {
        ids.map(MusicItem.song)
    }

    @Test func `playing songs starts the first, through the stream for it`() async {
        let player = player()

        player.play(songs("a", "b"))
        #expect(player.status == .loading)
        await startSong(1, in: player)

        #expect(player.status == .playing)
        #expect(player.current?.id == "a")
        #expect(streams.received == [SongStreams.Request(songID: "a", allowsDirect: true)])
        #expect(engine?.loads.first?.metadata.title == "Song a")
        #expect(engine?.isPlaying == true)
        #expect(MusicPlayer.active === player)
        player.stop()
    }

    @Test func `a song that ends hands over to the next once the server has heard`() async throws {
        let player = player()
        player.play(songs("a", "b"))
        await startSong(1, in: player)
        let first = engine

        first?.currentTime = .seconds(100)
        first?.send(.ended)
        await startSong(2, in: player)

        #expect(player.current?.id == "b")
        #expect(first?.isStopped == true)
        let stop = log.events.firstIndex { $0.hasPrefix("stopped") }
        let next = log.events.firstIndex(of: "loaded b directPlay")
        #expect(try #require(stop) < #require(next))
        player.stop()
    }

    @Test func `the end of the queue leaves it there, ready to play again`() async {
        let player = player()
        player.play(songs("a"))
        await startSong(1, in: player)

        engine?.send(.ended)
        #expect(await eventually { player.status == .ended })
        #expect(player.current?.id == "a")
        #expect(engines.made.count == 1)

        player.resume()
        await startSong(2, in: player)
        #expect(player.current?.id == "a")
        player.stop()
    }

    @Test func `repeating everything starts the queue again, and repeating one replays the song`() async {
        let player = player()
        player.play(songs("a", "b"))
        await startSong(1, in: player)
        player.cycleRepeatMode()
        #expect(player.queue.repeatMode == .all)

        player.next()
        await startSong(2, in: player)
        engine?.send(.ended)
        await startSong(3, in: player)
        #expect(player.current?.id == "a")

        player.cycleRepeatMode()
        #expect(player.queue.repeatMode == .one)
        engine?.send(.ended)
        await startSong(4, in: player)
        #expect(player.current?.id == "a")
        player.stop()
    }

    @Test func `previous goes back early in a song, and restarts it later`() async {
        let player = player()
        player.play(songs("a", "b"))
        await startSong(1, in: player)
        player.next()
        await startSong(2, in: player)

        engine?.currentTime = .seconds(10)
        #expect(await eventually { player.position == .seconds(10) })
        player.previous()
        #expect(await eventually { engine?.currentTime == .zero })
        #expect(player.current?.id == "b")

        player.previous()
        await startSong(3, in: player)
        #expect(player.current?.id == "a")
        player.stop()
    }

    @Test func `pause and resume act on the song's engine`() async {
        let player = player()
        player.play(songs("a"))
        await startSong(1, in: player)

        player.togglePlayPause()
        #expect(player.status == .paused)
        #expect(engine?.isPlaying == false)
        player.togglePlayPause()
        #expect(player.status == .playing)
        #expect(engine?.isPlaying == true)
        player.stop()
    }

    @Test func `a song that won't play directly is tried again as a transcode`() async {
        let player = player()
        player.play(songs("a"))
        await startSong(1, in: player)

        engine?.send(.failed(PlayerError.streamFailed(underlying: nil)))
        #expect(await eventually { streams.received.count == 2 })
        engine?.send(.ready)

        #expect(await eventually { player.status == .playing })
        #expect(streams.received.last == SongStreams.Request(songID: "a", allowsDirect: false))
        #expect(player.failure == nil)
        player.stop()
    }

    @Test func `a song the server can't send leaves the player failed, with the queue kept`() async {
        streams.fail = true
        let player = player()

        player.play(songs("a", "b"))

        #expect(await eventually { player.status == .failed })
        #expect(player.failure != nil)
        #expect(player.queue.entries.count == 2)
        streams.fail = false
        player.next()
        await startSong(2, in: player)
        #expect(player.current?.id == "b")
        player.stop()
    }

    @Test func `removing the song playing plays the next`() async {
        let player = player()
        player.play(songs("a", "b", "c"))
        await startSong(1, in: player)

        player.removeEntry(at: 0)
        await startSong(2, in: player)

        #expect(player.current?.id == "b")
        #expect(player.queue.entries.map(\.song.id) == ["b", "c"])
        player.removeEntry(at: 1)
        #expect(engines.made.count == 2)
        player.stop()
    }

    @Test func `stopping empties the queue and ends the song's session`() async {
        let player = player()
        player.play(songs("a", "b"))
        await startSong(1, in: player)

        player.stop()

        #expect(player.status == .idle)
        #expect(!player.hasQueue)
        #expect(MusicPlayer.active == nil)
        #expect(await eventually { log.events.contains { $0.hasPrefix("stopped") } })
        #expect(engine?.isStopped == true)
    }

    @Test func `starting a second player stops the first`() async {
        let first = player()
        first.play(songs("a"))
        await startSong(1, in: first)

        let second = player()
        second.play(songs("b"))

        #expect(first.status == .idle)
        #expect(MusicPlayer.active === second)
        second.stop()
    }

    @Test func `a video starting stops the music`() async {
        let player = player()
        player.play(songs("a"))
        await startSong(1, in: player)

        await MusicStopping().handle(.loaded(FakeStreams.stream("m1", method: .directPlay), .item("m1")), in: video())

        #expect(player.status == .idle)
        #expect(!player.hasQueue)
    }

    @Test func `the remote hears about each song and status`() async {
        let remote = RecordingRemote()
        let player = player(remote: remote)

        player.play(songs("a"))
        await startSong(1, in: player)
        player.pause()
        player.stop()

        #expect(remote.attached)
        #expect(remote.statuses.contains(.playing))
        #expect(remote.statuses.last == .paused)
        #expect(remote.detached)
    }

    private func video() -> PlaybackController {
        PlaybackController(
            request: PlaybackRequest(.item("m1")),
            engine: FakeEngine(),
            features: [],
            loadStream: FakeStreams().load,
        )
    }
}
