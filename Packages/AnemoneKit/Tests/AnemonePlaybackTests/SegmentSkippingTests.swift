import AnemoneCore
import AnemoneJellyfin
@testable import AnemonePlayback
import Foundation
import Synchronization
import Testing

/// Skipping segments, driven by a controller with a fake engine whose position the tests move.
@MainActor
struct SegmentSkippingTests {
    private let engine = FakeEngine()
    private let settings = SkipSettings()
    private let requested = RequestLog()

    private static let intro = MediaSegment(id: "intro", kind: .intro, start: .seconds(10), end: .seconds(40))
    private static let outro = MediaSegment(id: "outro", kind: .outro, start: .seconds(80), end: .seconds(90))
    /// Runs to the end of `FakeEngine`'s 100 s.
    private static let preview = MediaSegment(id: "preview", kind: .preview, start: .seconds(90), end: .seconds(101))
    private static let pastIntro = Self.intro.end + .milliseconds(1)

    private func controller(
        _ entries: [PlaybackQueue.Entry] = [.item("m1")],
        segments: [MediaSegment]? = [Self.intro, Self.outro, Self.preview],
        offerDuration: Duration = .seconds(10),
    ) throws -> (PlaybackController, SegmentSkipping) {
        let settings = settings
        let requested = requested
        let skipping = SegmentSkipping(
            load: { itemID in
                requested.append(itemID)
                guard let segments else { throw URLError(.notConnectedToInternet) }
                return segments
            },
            offerDuration: offerDuration,
            behavior: { settings.behaviors[$0] ?? .ignore },
        )
        let playback = try PlaybackController(
            request: PlaybackRequest(queue: #require(PlaybackQueue(entries: entries))),
            engine: engine,
            features: [skipping],
            positionInterval: .milliseconds(10),
            loadStream: FakeStreams().load,
        )
        return (playback, skipping)
    }

    /// Starts playing and waits for the segments.
    private func play(_ playback: PlaybackController, _ skipping: SegmentSkipping) async {
        await playback.start()
        engine.send(.ready)
        #expect(await eventually { !skipping.segments.isEmpty })
    }

    /// Lets a few positions go by.
    private func settle() async {
        try? await Task.sleep(for: .milliseconds(100))
    }

    @Test func `asking shows a button that skips just past the segment, and only once`() async throws {
        settings.behaviors[.intro] = .ask
        let (playback, skipping) = try controller()
        await play(playback, skipping)

        engine.currentTime = .seconds(12)
        #expect(await eventually { !playback.accessories.actions.isEmpty })
        let action = try #require(playback.accessories.actions.first)
        #expect(action.id == SegmentSkipping.skipActionID)
        #expect(action.title == "Skip Intro")
        #expect(skipping.offered == Self.intro)

        action.perform()
        #expect(await eventually { engine.currentTime == Self.pastIntro })
        #expect(playback.accessories.actions.isEmpty)
        #expect(skipping.offered == nil)

        // Seeking back into it plays it without asking again.
        engine.currentTime = .seconds(15)
        await settle()
        #expect(playback.accessories.actions.isEmpty)
        #expect(skipping.current == Self.intro)
        #expect(engine.currentTime == .seconds(15))
        await playback.stop()
    }

    @Test func `the button goes after a while and doesn't come back for that segment`() async throws {
        settings.behaviors[.intro] = .ask
        let (playback, skipping) = try controller(offerDuration: .milliseconds(50))
        await play(playback, skipping)

        engine.currentTime = .seconds(12)
        #expect(await eventually { !playback.accessories.actions.isEmpty })
        #expect(await eventually { playback.accessories.actions.isEmpty })
        await settle()

        #expect(playback.accessories.actions.isEmpty)
        #expect(skipping.offered == nil)
        #expect(skipping.current == Self.intro)
        await playback.stop()
    }

    @Test func `auto-skip jumps past the segment once, and plays it after seeking back`() async throws {
        settings.behaviors[.intro] = .autoSkip
        let (playback, skipping) = try controller()
        await play(playback, skipping)

        engine.currentTime = .seconds(12)
        #expect(await eventually { engine.currentTime == Self.pastIntro })
        #expect(playback.accessories.actions.isEmpty)

        engine.currentTime = .seconds(15)
        await settle()
        #expect(engine.currentTime == .seconds(15))
        await playback.stop()
    }

    @Test func `ignored segments play, with no button`() async throws {
        let (playback, skipping) = try controller()
        await play(playback, skipping)

        engine.currentTime = .seconds(12)
        #expect(await eventually { skipping.current == Self.intro })
        await settle()

        #expect(playback.accessories.actions.isEmpty)
        #expect(engine.currentTime == .seconds(12))
        await playback.stop()
    }

    @Test func `the segment playing is published whatever the setting, for Up Next`() async throws {
        settings.behaviors[.outro] = .ignore
        let (playback, skipping) = try controller()
        var changes: [MediaSegment?] = []
        skipping.onChange = { changes.append($0) }
        await play(playback, skipping)

        engine.currentTime = .seconds(85)
        #expect(await eventually { changes == [Self.outro] })
        #expect(skipping.current == Self.outro)
        engine.currentTime = .seconds(50)
        #expect(await eventually { changes == [Self.outro, nil] })
        #expect(skipping.current == nil)
        await playback.stop()
    }

    @Test func `the button waits while a card asks something, as for Up Next`() async throws {
        settings.behaviors[.outro] = .ask
        let (playback, skipping) = try controller()
        playback.accessories.show(PlayerCard(id: "upNext", title: "Up Next", actions: []))
        await play(playback, skipping)

        engine.currentTime = .seconds(85)
        #expect(await eventually { skipping.current == Self.outro })
        await settle()
        #expect(playback.accessories.actions.isEmpty)

        playback.accessories.dismissCard("upNext")
        #expect(await eventually { playback.accessories.actions.first?.title == "Skip Outro" })
        await playback.stop()
    }

    @Test func `a segment running to the end skips to the end`() async throws {
        settings.behaviors[.preview] = .autoSkip
        let (playback, skipping) = try controller()
        await play(playback, skipping)

        engine.currentTime = .seconds(95)

        #expect(await eventually { engine.currentTime == .seconds(100) })
        await playback.stop()
    }

    @Test func `the next entry is skipped afresh, but a retry as a transcode isn't`() async throws {
        settings.behaviors[.intro] = .autoSkip
        let (playback, skipping) = try controller([.item("m1"), .item("m2")])
        await play(playback, skipping)
        engine.currentTime = .seconds(12)
        #expect(await eventually { engine.currentTime == Self.pastIntro })

        // Direct play fails back inside the intro, and the transcode starts there.
        engine.currentTime = .seconds(15)
        engine.send(.failed(PlayerError.streamFailed(underlying: nil)))
        #expect(await eventually { engine.loads.count == 2 })
        engine.send(.ready)
        await settle()
        #expect(engine.currentTime == .seconds(15))

        playback.playNext()
        #expect(await eventually { engine.loads.count == 3 })
        engine.send(.ready)
        engine.currentTime = .seconds(12)
        #expect(await eventually { engine.currentTime == Self.pastIntro })
        #expect(requested.itemIDs == ["m1", "m2"])
        await playback.stop()
    }

    @Test func `without segments from the server, nothing changes`() async throws {
        settings.behaviors[.intro] = .autoSkip
        let (playback, skipping) = try controller(segments: nil)
        await playback.start()
        engine.send(.ready)
        #expect(await eventually { requested.itemIDs.count == 1 })

        engine.currentTime = .seconds(12)
        await settle()

        #expect(skipping.segments.isEmpty)
        #expect(skipping.current == nil)
        #expect(engine.currentTime == .seconds(12))
        await playback.stop()
    }

    @Test func `closing the player leaves the segment`() async throws {
        settings.behaviors[.intro] = .ask
        let (playback, skipping) = try controller()
        await play(playback, skipping)
        engine.currentTime = .seconds(12)
        #expect(await eventually { skipping.offered != nil })

        await playback.stop()

        #expect(skipping.current == nil)
        #expect(skipping.offered == nil)
        #expect(playback.accessories.actions.isEmpty)
    }

    @Test func `another entry starts with no segment playing and no button`() async throws {
        settings.behaviors[.intro] = .ask
        let (playback, skipping) = try controller([.item("e1"), .item("e2")])
        await play(playback, skipping)
        engine.currentTime = .seconds(12)
        #expect(await eventually { skipping.offered == Self.intro })

        // The next entry's stream loads before the first one's `stopped` reaches the feature.
        playback.play(entryAt: 1)
        let next = PlaybackStream(itemID: "e2", url: URL(filePath: "/e2"), method: .directPlay)
        await skipping.handle(.loaded(next, playback.queue.current), in: playback)

        #expect(skipping.current == nil)
        #expect(skipping.offered == nil)
        #expect(playback.accessories.actions.isEmpty)
        await playback.stop()
    }

    @Test func `wholphin's defaults ask about intros, outros and ads, and play recaps and previews`() {
        let defaults = MediaSegment.Kind.allCases.map { Preferences.skipBehavior(for: $0).defaultValue }

        #expect(defaults == [.ask, .ask, .ignore, .ignore, .ask])
        #expect(Preferences.skipIntros.key == "skipIntros")
        #expect(Preferences.skipCommercials.key == "skipCommercials")
    }

    @Test func `fake segments for debug builds are read as kinds and seconds`() {
        let fakes = MediaSegment.fakes("outro:60-75, intro:5-20")

        #expect(fakes?.map(\.kind) == [.intro, .outro])
        #expect(fakes?.first?.start == .seconds(5))
        #expect(fakes?.first?.end == .seconds(20))
        #expect(MediaSegment.fakes("intro:20-5") == nil)
        #expect(MediaSegment.fakes("credits:5-20") == nil)
        #expect(MediaSegment.fakes("intro:5-20,outro") == nil)
        #expect(MediaSegment.fakes("") == nil)
    }
}

/// The skip settings a test chose; the rest are ignored.
@MainActor
private final class SkipSettings {
    var behaviors: [MediaSegment.Kind: SkipSegmentBehavior] = [:]
}

/// The items whose segments were asked for.
private final class RequestLog: Sendable {
    private let requests = Mutex<[String]>([])

    var itemIDs: [String] {
        requests.withLock(\.self)
    }

    func append(_ itemID: String) {
        requests.withLock { $0.append(itemID) }
    }
}
