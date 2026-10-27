import AnemoneJellyfin
@testable import AnemonePlayback
import Testing

/// Moving on from the credits with the overlay or the remote, the skip button going while it has
/// focus, and a seek still being chosen as a pre-roll gives way to the movie.
@MainActor
extension PlayerOverlayTests {
    private nonisolated static let outro = MediaSegment(id: "o1", kind: .outro, start: .seconds(70), end: .seconds(95))

    /// A player of three entries whose credits start at 70 s, with a log of what features hear.
    private func creditsPlayer() async throws -> (PlaybackController, EventLog) {
        let skipping = SegmentSkipping(load: { _ in [Self.outro] }, behavior: { _ in .ignore })
        let log = EventLog()
        let playback = try controller([.item("e1"), .item("e2"), .item("e3")], features: [skipping, log])
        try await play(playback)
        #expect(await eventually { !skipping.segments.isEmpty })
        return (playback, log)
    }

    @Test func `next and the queue row from the credits end the entry as played, as Up Next does`() async throws {
        let (playback, log) = try await creditsPlayer()
        let skipping = try #require(playback.feature(SegmentSkipping.self))
        let overlay = overlay(playback)

        // Before the credits, Next ends the entry where it is.
        engine.currentTime = .seconds(40)
        overlay.next()
        #expect(await eventually { log.events.contains("stopped 40.0 seconds") })
        #expect(await eventually { engine.loads.count == 2 })
        engine.send(.ready)
        #expect(await eventually { log.events.count(where: { $0.hasPrefix("started") }) == 2 })
        #expect(await eventually { !skipping.segments.isEmpty })

        // In the credits, the queue row ends it at its end, so the server marks it played.
        engine.currentTime = .seconds(80)
        overlay.play(entryAt: 2)

        #expect(await eventually { log.events.contains("stopped 100.0 seconds") })
        #expect(playback.queue.current.itemID == "e3")
    }

    @Test func `the remote's Next from the credits ends the entry as played`() async throws {
        let (playback, log) = try await creditsPlayer()
        engine.currentTime = .seconds(80)
        #expect(playback.hasReachedCredits)

        playback.playNext()

        #expect(await eventually { log.events.contains("stopped 100.0 seconds") })
    }

    @Test func `when its segment ends under focus, the skip button sends focus to Play and Pause`() async throws {
        let intro = MediaSegment(id: "intro", kind: .intro, start: .seconds(10), end: .seconds(40))
        let skipping = SegmentSkipping(
            load: { _ in [intro] },
            offerDuration: .milliseconds(10),
            behavior: { _ in .ask },
        )
        let playback = try controller(features: [skipping])
        try await play(playback)
        #expect(await eventually { !skipping.segments.isEmpty })
        let overlay = overlay(playback)
        // The button over the video comes and goes; then the controls offer to skip the rest.
        engine.currentTime = .seconds(12)
        #expect(await eventually { skipping.current == intro && skipping.offered == nil })
        overlay.showControls()
        // As the overlay's view tells it when the button takes focus.
        overlay.focus = .skipButton
        #expect(overlay.skippableSegment == intro)
        #expect(!overlay.skipButtonLeftFocus)

        engine.currentTime = .seconds(41)

        #expect(await eventually { overlay.skipButtonLeftFocus })
        // With focus anywhere else, nothing moves it.
        overlay.focus = .control
        #expect(!overlay.skipButtonLeftFocus)
    }

    @Test func `a seek still being chosen as a pre-roll gives way to the movie is dropped`() async throws {
        let preroll = PlaybackQueue.Entry(itemID: "i1", metadata: PlaybackMetadata(title: "Pre-roll"), isIntro: true)
        let playback = try controller([preroll, .item("m1")])
        try await play(playback)
        engine.duration = .seconds(6)
        engine.currentTime = .seconds(5)
        let overlay = overlay(playback)
        // A press that's done, its seek not yet made, and another still held.
        #expect(tap(.rightArrow, on: overlay) == .handled)
        #expect(overlay.seeker.target == .seconds(6))
        #expect(overlay.pressBegan(.rightArrow) == .handled)

        engine.send(.ended)
        #expect(await eventually { playback.queue.current.itemID == "m1" })
        // As the overlay's view does when the entry changes.
        overlay.entryChanged()

        #expect(!overlay.seeker.isSeeking)
        #expect(!overlay.showsSeekBar)
        engine.duration = .seconds(100)
        engine.currentTime = .zero
        #expect(overlay.pressEnded(.rightArrow) == .handled)
        #expect(!overlay.seeker.isSeeking)
        overlay.seeker.commit()
        try await Task.sleep(for: .milliseconds(50))
        // The movie plays from its start, not 6 s in.
        #expect(engine.currentTime == .zero)
    }
}
