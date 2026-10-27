@testable import AnemonePlayback
import Testing

/// Seeking through the engine: steps that add up and are seeked once, held presses that speed
/// up, swipes, and jumps.
@MainActor
struct SeekerTests {
    private let engine = FakeEngine()

    private func seeker(commitDelay: Duration = .milliseconds(30)) -> Seeker {
        Seeker(
            engine: engine,
            skipBack: .seconds(10),
            skipForward: .seconds(30),
            timing: Seeker.Timing(
                commitDelay: commitDelay,
                repeatDelay: .milliseconds(20),
                repeatInterval: .milliseconds(2),
            ),
        )
    }

    @Test func `steps add up and are seeked once the user stops`() async {
        engine.currentTime = .seconds(10)
        let seeker = seeker()

        seeker.step(.forward)
        seeker.step(.forward)
        seeker.step(.back)

        #expect(seeker.target == .seconds(60))
        #expect(seeker.shownPosition == .seconds(60))
        #expect(engine.currentTime == .seconds(10))
        #expect(await eventually { seeker.target == nil })
        #expect(engine.currentTime == .seconds(60))
        #expect(seeker.position == .seconds(60))
    }

    @Test func `stays within the video`() {
        engine.currentTime = .seconds(5)
        let seeker = seeker(commitDelay: .seconds(60))

        seeker.step(.back)
        #expect(seeker.target == .zero)

        seeker.step(.forward, steps: 10)
        #expect(seeker.target == .seconds(100))
    }

    @Test func `commits at once, or not at all when cancelled`() async {
        engine.currentTime = .seconds(20)
        let seeker = seeker(commitDelay: .seconds(60))

        seeker.step(.forward)
        seeker.commit()
        #expect(await eventually { engine.currentTime == .seconds(50) })
        #expect(seeker.target == nil)

        seeker.step(.back)
        seeker.cancel()
        #expect(seeker.target == nil)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(engine.currentTime == .seconds(50))
    }

    @Test func `a quick press seeks one step`() {
        engine.currentTime = .seconds(40)
        let seeker = seeker(commitDelay: .seconds(60))

        seeker.pressBegan(.back, ignoredRepeats: SeekAcceleration.hiddenControlsIgnoredRepeats)
        #expect(seeker.isHolding)
        seeker.pressEnded()

        #expect(!seeker.isHolding)
        #expect(seeker.target == .seconds(30))
    }

    @Test func `a held press keeps seeking, and letting go doesn't add a step`() async throws {
        engine.duration = .seconds(5400)
        engine.currentTime = .seconds(60)
        let seeker = seeker(commitDelay: .milliseconds(20))

        seeker.pressBegan(.forward, ignoredRepeats: 0)
        #expect(await eventually { (seeker.target ?? .zero) >= .seconds(360) })
        // Nothing is seeked while the press is held.
        #expect(engine.currentTime == .seconds(60))
        seeker.pressEnded()
        let target = try #require(seeker.target)

        #expect(await eventually { seeker.target == nil })
        #expect(engine.currentTime == target)
        // Whole steps of 30 s.
        #expect((target - .seconds(60)).components.seconds.isMultiple(of: 30))
    }

    @Test func `a cancelled press doesn't step`() {
        engine.currentTime = .seconds(40)
        let seeker = seeker(commitDelay: .seconds(60))

        seeker.pressBegan(.forward, ignoredRepeats: SeekAcceleration.hiddenControlsIgnoredRepeats)
        seeker.pressCancelled()

        #expect(seeker.target == nil)
        #expect(!seeker.isHolding)
    }

    @Test func `a swipe scrubs from where it began`() async {
        engine.duration = .seconds(1200)
        engine.currentTime = .seconds(300)
        let seeker = seeker()
        seeker.refresh()

        seeker.swipeBegan()
        seeker.swipeMoved(translation: 480, width: 1920)
        #expect(seeker.target == .seconds(360))
        seeker.swipeMoved(translation: -960, width: 1920)
        #expect(seeker.target == .seconds(180))
        // Nothing is seeked while the finger is down.
        try? await Task.sleep(for: .milliseconds(60))
        #expect(engine.currentTime == .seconds(300))

        seeker.swipeEnded()
        #expect(await eventually { seeker.target == nil })
        #expect(engine.currentTime == .seconds(180))
    }

    @Test func `jumps straight to a position`() async {
        let seeker = seeker(commitDelay: .seconds(60))

        seeker.jump(to: .seconds(42))

        #expect(seeker.target == .seconds(42))
        #expect(await eventually { seeker.target == nil })
        #expect(engine.currentTime == .seconds(42))
    }
}
