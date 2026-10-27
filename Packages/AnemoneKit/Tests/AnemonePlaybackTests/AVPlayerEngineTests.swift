@testable import AnemonePlayback
import Foundation
import Testing

/// The AVPlayer engine itself, where it can run without a screen.
@MainActor
struct AVPlayerEngineTests {
    @Test func `a stream loaded while the player was playing waits for play`() {
        let engine = AVPlayerEngine()
        // As after a stream that failed partway: AVPlayer keeps its rate for the next item, so
        // it would start from 0 before the resume position.
        engine.player.rate = 1

        _ = engine.load(URL(filePath: "/missing.mp4"), from: .seconds(30), metadata: PlaybackMetadata(title: "Film"))

        #expect(engine.player.rate == 0)
        engine.stop()
    }
}
