import AnemoneCore
import AnemoneJellyfin
@testable import AnemonePlayback
import Foundation
import Testing

/// Picks that come while the server is asked for a stream: one made before the request was
/// prepared is in it, so it doesn't ask the server again.
@MainActor
struct TrackSelectionReloadTests {
    private let engine = TrackEngine()
    private let log = EventLog()
    private let requests = StreamRequestLog()
    private let defaults: UserDefaults

    init() throws {
        let suite = "TrackSelectionReloadTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
    }

    private func pick(_ optionID: String, in menuID: String, of playback: PlaybackController) throws {
        let menu = playback.accessories.menus.first { $0.id == menuID }
        try #require(menu?.options.first { $0.id == optionID }).select()
    }

    @Test func `a pick while features prepare the request is in it, without asking again`() async throws {
        let slow = SlowPreparing()
        let selection = TrackSelection(
            server: TrackSelection.Server(
                itemTracks: { ItemTracks(itemID: $0, sources: [.init(id: $0, tracks: .multiTrack)]) },
                profileSettings: { .english },
            ),
            store: TrackChoiceStore(userID: "u1", defaults: defaults),
            defaults: defaults,
        )
        let playback = PlaybackController(
            request: PlaybackRequest(.item("m1")),
            engine: engine,
            // A feature before track selection that takes its time preparing.
            features: [slow, selection, log],
        ) { [requests] request in
            requests.append(request)
            return PlaybackStream.hls(request.itemID, request.tracks, method: .directStream)
        }
        await playback.start()
        engine.send(.ready)
        _ = await eventually { log.events.contains { $0.hasPrefix("started") } }

        // French takes another stream; Japanese is picked while that request is prepared.
        slow.holds = true
        try pick("audio.2", in: "audio", of: playback)
        #expect(await eventually { slow.isHolding })
        try pick("audio.3", in: "audio", of: playback)
        try? await Task.sleep(for: .milliseconds(50))
        slow.release()

        #expect(await eventually { log.events.contains { $0.hasPrefix("reloaded") } })
        try? await Task.sleep(for: .milliseconds(100))
        #expect(requests.sent.map(\.audioStreamIndex) == [1, 3])
        #expect(engine.loads.count == 2)
        #expect(log.events.count { $0.hasPrefix("stopped") } == 1)
        await playback.stop()
    }

    @Test func `a pick after the request was prepared still asks again`() async throws {
        let slow = SlowPreparing()
        let selection = TrackSelection(
            server: TrackSelection.Server(
                itemTracks: { ItemTracks(itemID: $0, sources: [.init(id: $0, tracks: .multiTrack)]) },
                profileSettings: { .english },
            ),
            store: TrackChoiceStore(userID: "u1", defaults: defaults),
            defaults: defaults,
        )
        let playback = PlaybackController(
            request: PlaybackRequest(.item("m1")),
            engine: engine,
            // A feature after track selection that takes its time preparing.
            features: [selection, slow, log],
        ) { [requests] request in
            requests.append(request)
            return PlaybackStream.hls(request.itemID, request.tracks, method: .directStream)
        }
        await playback.start()
        engine.send(.ready)
        _ = await eventually { log.events.contains { $0.hasPrefix("started") } }

        slow.holds = true
        try pick("audio.2", in: "audio", of: playback)
        #expect(await eventually { slow.isHolding })
        try pick("audio.3", in: "audio", of: playback)
        try? await Task.sleep(for: .milliseconds(50))
        slow.release()

        #expect(await eventually { requests.sent.count == 3 })
        #expect(await eventually { engine.loads.count == 2 })
        #expect(requests.sent.map(\.audioStreamIndex) == [1, 2, 3])
        await playback.stop()
    }
}

/// A feature whose `prepare(_:)` waits, while `holds`, until the test releases it.
@MainActor
private final class SlowPreparing: PlaybackFeature {
    var holds = false
    private(set) var isHolding = false
    private var waiting: CheckedContinuation<Void, Never>?

    func handle(_: PlaybackEvent, in _: PlaybackController) async {}

    func prepare(_: inout StreamRequest) async {
        guard holds else { return }
        holds = false
        isHolding = true
        await withCheckedContinuation { waiting = $0 }
        isHolding = false
    }

    func release() {
        waiting?.resume()
        waiting = nil
    }
}
