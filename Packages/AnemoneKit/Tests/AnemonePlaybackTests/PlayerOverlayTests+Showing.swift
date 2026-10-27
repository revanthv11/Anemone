import AnemoneJellyfin
@testable import AnemonePlayback
import Testing

/// What the overlay shows besides the transport: the position, read only while something shows
/// it, and the controls' button that skips the rest of a segment.
@MainActor
extension PlayerOverlayTests {
    @Test func `the controls and the compact seek bar read the position as they show`() async throws {
        let playback = try controller()
        try await play(playback)
        let overlay = overlay(playback)
        #expect(!overlay.showsPosition)

        engine.currentTime = .seconds(40)
        overlay.showControls()
        #expect(overlay.showsPosition)
        #expect(overlay.seeker.position == .seconds(40))

        #expect(tap(.menu, on: overlay) == .handled)
        #expect(!overlay.showsPosition)

        engine.currentTime = .seconds(55)
        #expect(overlay.pressBegan(.rightArrow) == .handled)
        #expect(overlay.showsPosition)
        #expect(overlay.seeker.position == .seconds(55))
        _ = overlay.pressEnded(.rightArrow)
        #expect(overlay.seeker.target == .seconds(85))
    }

    @Test func `a swipe scrubs by the video's length as the swipe begins`() async throws {
        let playback = try controller()
        try await play(playback)
        // Not known yet when the overlay came up, and nothing has read it since.
        engine.duration = nil
        let overlay = overlay(playback)
        engine.duration = .seconds(3000)
        engine.currentTime = .seconds(10)

        overlay.swipeBegan()
        overlay.swipeMoved(translation: 960, width: 1920)
        overlay.swipeEnded()

        // A 50-minute video scrubs 10 minutes a swipe, so half a swipe is 5 minutes.
        #expect(overlay.seeker.target == .seconds(310))
    }

    @Test func `the controls skip the rest of a segment the user doesn't ignore`() async throws {
        let intro = MediaSegment(id: "intro", kind: .intro, start: .seconds(10), end: .seconds(40))
        let recap = MediaSegment(id: "recap", kind: .recap, start: .seconds(50), end: .seconds(60))
        let outro = MediaSegment(id: "outro", kind: .outro, start: .seconds(70), end: .seconds(90))
        let behaviors: [MediaSegment.Kind: SkipSegmentBehavior] = [.intro: .ask, .recap: .ignore, .outro: .autoSkip]
        let skipping = SegmentSkipping(
            load: { _ in [intro, recap, outro] },
            offerDuration: .seconds(60),
            behavior: { behaviors[$0] ?? .ignore },
        )
        let playback = try controller(features: [skipping])
        try await play(playback)
        #expect(await eventually { !skipping.segments.isEmpty })
        let overlay = overlay(playback) { behaviors[$0] ?? .ignore }
        overlay.showControls()

        // While the segment's own button shows, the controls have it among their actions.
        engine.currentTime = .seconds(12)
        #expect(await eventually { skipping.offered == intro })
        #expect(overlay.skippableSegment == nil)

        // A kind the user ignores gets no button.
        engine.currentTime = .seconds(52)
        #expect(await eventually { skipping.current == recap })
        #expect(overlay.skippableSegment == nil)

        // Back in credits that were skipped once, the controls offer to skip the rest.
        engine.currentTime = .seconds(72)
        #expect(await eventually { engine.currentTime > outro.end })
        engine.currentTime = .seconds(75)
        #expect(await eventually { skipping.current == outro })
        #expect(overlay.skippableSegment == outro)
        overlay.skipRest(of: outro)
        #expect(await eventually { engine.currentTime == outro.end })
        #expect(await eventually { overlay.skippableSegment == nil })
        #expect(overlay.controlsVisible)
    }

    @Test func `skipping a segment that runs past the end goes to the end`() async throws {
        let credits = MediaSegment(id: "credits", kind: .outro, start: .seconds(80), end: .seconds(500))
        let playback = try controller()
        try await play(playback)
        let overlay = overlay(playback)

        overlay.skipRest(of: credits)

        #expect(await eventually { engine.currentTime == .seconds(100) })
    }
}
