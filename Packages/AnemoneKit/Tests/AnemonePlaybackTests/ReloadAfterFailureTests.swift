import AnemoneJellyfin
@testable import AnemonePlayback
import Foundation
import Testing

/// A reload, such as a track pick, that comes while features hear that the stream failed.
@MainActor
struct ReloadAfterFailureTests {
    @Test func `a reload while a failed direct play is handled asks for the transcode, not the same stream`() async {
        let engine = FakeEngine()
        let log = EventLog()
        let streams = FakeStreams()
        let playback = PlaybackController(
            request: PlaybackRequest(.item("m1")),
            engine: engine,
            features: [log],
            positionInterval: .seconds(60),
            loadStream: streams.load,
        )
        log.onEvent = { event, controller in
            if case .failed = event {
                controller.reload()
            }
        }
        await playback.start()
        engine.send(.ready)
        _ = await eventually { log.events.contains { $0.hasPrefix("started") } }

        engine.send(.failed(PlayerError.streamFailed(underlying: nil)))

        #expect(await eventually { streams.received.count == 2 })
        try? await Task.sleep(for: .milliseconds(100))
        #expect(streams.received.map(\.allowsDirect) == [true, false])
        #expect(engine.loads.count == 2)
        await playback.stop()
    }
}
