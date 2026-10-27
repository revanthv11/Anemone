import AnemoneJellyfin
@testable import AnemonePlayback
import Foundation
import Synchronization
import Testing

/// A player closed while its cinema intros are looked up.
@MainActor
struct CinemaIntrosStopTests {
    @Test func `closing while the intros are looked up looks for nothing more`() async throws {
        let engine = FakeEngine()
        let streams = FakeStreams()
        let calls = Calls()
        let (lookup, finishLookup) = AsyncStream.makeStream(of: Void.self)
        let request = try PlaybackRequest(
            queue: #require(PlaybackQueue(entries: [.item("m1")])),
            following: {
                calls.note("following")
                return [.item("m2")]
            },
            intros: { _ in
                calls.note("intros")
                for await _ in lookup {}
                return CinemaIntros.entries(for: [MediaItem(id: "i1", name: "Pre-roll", kind: .video)])
            },
        )
        let playback = PlaybackController(
            request: request,
            engine: engine,
            features: [],
            positionInterval: .milliseconds(10),
            loadStream: streams.load,
        )
        let starting = Task { await playback.start() }
        #expect(await eventually { calls.list == ["intros"] })

        await playback.stop()
        finishLookup.finish()
        await starting.value
        try await Task.sleep(for: .milliseconds(50))

        // Nothing went on after `stop()`, where nothing would have cancelled it.
        #expect(calls.list == ["intros"])
        #expect(streams.received.isEmpty)
        #expect(playback.queue.entries.map(\.itemID) == ["m1"])
    }
}

/// What a request's closures were asked, in order.
private final class Calls: Sendable {
    private let calls = Mutex<[String]>([])

    var list: [String] {
        calls.withLock(\.self)
    }

    func note(_ call: String) {
        calls.withLock { $0.append(call) }
    }
}
