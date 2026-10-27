import AnemoneCore
@testable import AnemonePlayback
import Testing

/// Skipping back when playback resumes after a pause, with a fake engine.
@MainActor
struct SkipBackOnResumeTests {
    private let engine = FakeEngine()

    /// Playing, at `position`.
    private func playing(
        skippingBack skip: @escaping @MainActor () -> Duration,
        at position: Duration,
    ) async throws -> PlaybackController {
        let playback = try PlaybackController(
            request: PlaybackRequest(queue: #require(PlaybackQueue(entries: [.item("m1", from: position)]))),
            engine: engine,
            features: [SkipBackOnResume(setting: skip)],
            loadStream: FakeStreams().load,
        )
        await playback.start()
        engine.currentTime = position
        engine.send(.ready)
        #expect(await eventually { engine.isPlaying })
        return playback
    }

    @Test func `resuming goes back by the setting`() async throws {
        let playback = try await playing(skippingBack: { .seconds(10) }, at: .seconds(1080))
        // Starting from the resume position doesn't count.
        try await Task.sleep(for: .milliseconds(50))
        #expect(engine.currentTime == .seconds(1080))

        engine.pause()
        engine.currentTime = .seconds(1090)
        engine.play()

        #expect(await eventually { engine.currentTime == .seconds(1080) })
        await playback.stop()
    }

    @Test func `not before the start`() async throws {
        let playback = try await playing(skippingBack: { .seconds(10) }, at: .seconds(4))

        engine.pause()
        engine.play()

        #expect(await eventually { engine.currentTime == .zero })
        await playback.stop()
    }

    @Test func `off by default, as in Wholphin`() async throws {
        #expect(Preferences.skipBackOnResume.defaultValue == 0)
        let playback = try await playing(skippingBack: { .zero }, at: .seconds(300))

        engine.pause()
        engine.play()

        try await Task.sleep(for: .milliseconds(100))
        #expect(engine.currentTime == .seconds(300))
        await playback.stop()
    }
}
