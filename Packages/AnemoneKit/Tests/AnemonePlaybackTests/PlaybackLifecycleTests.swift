@testable import AnemonePlayback
import Testing

/// Pausing when the app goes to the background, with a fake engine and app.
@MainActor
struct PlaybackLifecycleTests {
    private let engine = FakeEngine()
    private let app = FakeApp()
    private let log = EventLog()

    private func controller(pausesInBackground: Bool = true) throws -> PlaybackController {
        let app = app
        let lifecycle = PlaybackLifecycle(
            changes: { app.changes() },
            isInBackground: { app.isInBackground },
            keepAlive: { app.keepAlives += 1 },
        )
        lifecycle.pausesInBackground = pausesInBackground
        return try PlaybackController(
            request: PlaybackRequest(queue: #require(PlaybackQueue(entries: [.item("m1")]))),
            engine: engine,
            features: [log, lifecycle],
            loadStream: FakeStreams().load,
        )
    }

    /// The last event other than the position ticking.
    private var lastChange: String? {
        log.events.last { $0 != "position" }
    }

    private func play(_ playback: PlaybackController) async {
        await playback.start()
        engine.send(.ready)
        #expect(await eventually { log.events.contains { $0.hasPrefix("started") } })
    }

    @Test func `going to the background pauses, and coming back plays on`() async throws {
        let playback = try controller()
        await play(playback)

        app.send(.background)

        #expect(await eventually { !engine.isPlaying })
        // The pause reaches features, so it's reported, while tvOS gives the app time.
        #expect(await eventually { lastChange?.hasPrefix("paused") == true })
        #expect(app.keepAlives == 1)

        app.send(.foreground)

        #expect(await eventually { engine.isPlaying })
        await playback.stop()
    }

    @Test func `paused before going away, it stays paused`() async throws {
        let playback = try controller()
        await play(playback)
        engine.pause()
        #expect(await eventually { lastChange?.hasPrefix("paused") == true })

        app.send(.background)
        app.send(.foreground)

        try await Task.sleep(for: .milliseconds(100))
        #expect(!engine.isPlaying)
        #expect(app.keepAlives == 0)
        await playback.stop()
    }

    @Test func `a stream that gets going while the app is away is paused`() async throws {
        let playback = try controller()
        await playback.start()
        #expect(await eventually { app.isWatched })

        app.send(.background)
        try await Task.sleep(for: .milliseconds(50))
        engine.send(.ready)

        #expect(await eventually { lastChange?.hasPrefix("paused") == true })
        #expect(!engine.isPlaying)
        app.send(.foreground)
        #expect(await eventually { engine.isPlaying })
        await playback.stop()
    }

    @Test func `going home while the stream is still loading pauses it once it gets going`() async throws {
        let playback = try controller()
        // Before the player hears anything from the app.
        app.isInBackground = true

        await playback.start()
        engine.send(.ready)

        #expect(await eventually { lastChange?.hasPrefix("paused") == true })
        #expect(!engine.isPlaying)
        #expect(app.keepAlives == 1)
        app.isInBackground = false
        app.send(.foreground)
        #expect(await eventually { engine.isPlaying })
        await playback.stop()
    }

    @Test func `players that go on in the background are left alone`() async throws {
        let playback = try controller(pausesInBackground: false)
        await play(playback)

        app.send(.background)

        try await Task.sleep(for: .milliseconds(100))
        #expect(engine.isPlaying)
        await playback.stop()
    }

    @Test func `it stops watching the app when the session ends`() async throws {
        let playback = try controller()
        await play(playback)
        #expect(app.isWatched)

        await playback.stop()

        #expect(await eventually { !app.isWatched })
    }
}

/// The app going to and from the background, as the tests say.
@MainActor
final class FakeApp {
    var keepAlives = 0
    /// What the app's state says, as against what it announces.
    var isInBackground = false
    private var continuation: AsyncStream<PlaybackLifecycle.Change>.Continuation?

    var isWatched: Bool {
        continuation != nil
    }

    func changes() -> AsyncStream<PlaybackLifecycle.Change> {
        let (stream, continuation) = AsyncStream.makeStream(of: PlaybackLifecycle.Change.self)
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.continuation = nil }
        }
        self.continuation = continuation
        return stream
    }

    func send(_ change: PlaybackLifecycle.Change) {
        continuation?.yield(change)
    }
}
