import AnemoneJellyfin
@testable import AnemonePlayback
import Testing

/// Seeking while the song's engine takes its time to get there.
extension MusicPlayerTests {
    @Test func `a seek keeps its position until the engine gets there, so Previous twice goes back a song`() async {
        let gate = LoadGate()
        var made: [SeekHoldingEngine] = []
        let player = MusicPlayer(
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
        player.play(songs("a", "b"))
        _ = await eventually { made.count == 1 && made.last?.base.loads.isEmpty == false }
        made.last?.base.send(.ready)
        #expect(await eventually { player.status == .playing })
        player.next()
        _ = await eventually { made.count == 2 && made.last?.base.loads.isEmpty == false }
        made.last?.base.send(.ready)
        #expect(await eventually { player.status == .playing })
        made.last?.base.currentTime = .seconds(10)
        #expect(await eventually { player.position == .seconds(10) })

        // Late in the song, Previous restarts it; the engine is still at 10 s meanwhile.
        player.previous()
        #expect(await eventually { gate.isReached })
        #expect(player.current?.id == "b")
        // Ticks while the seek is under way leave the position at the start.
        let ticked = await eventually(timeout: .milliseconds(100)) { player.position != .zero }
        #expect(!ticked)

        // So a second Previous, early in the song, goes back a song.
        player.previous()
        #expect(player.current?.id == "a")
        gate.open()
        _ = await eventually { made.count == 3 && made.last?.base.loads.isEmpty == false }
        made.last?.base.send(.ready)
        #expect(await eventually { player.status == .playing })
        #expect(player.current?.id == "a")
        player.stop()
    }
}
