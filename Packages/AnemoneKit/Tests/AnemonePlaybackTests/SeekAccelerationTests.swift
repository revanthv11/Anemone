@testable import AnemonePlayback
import Testing

/// Hold-to-seek acceleration, with Wholphin's `SeekAccelerationTest` ported first.
struct SeekAccelerationTests {
    @Test func `returns one when not repeating`() {
        #expect(SeekAcceleration.multiplier(repeatCount: 0, duration: .seconds(30)) == 1)
    }

    @Test func `an unknown duration doesn't accelerate`() {
        #expect(SeekAcceleration.multiplier(repeatCount: 89, duration: .zero) == 1)
        #expect(SeekAcceleration.multiplier(repeatCount: 300, duration: .milliseconds(-1)) == 1)
    }

    @Test func `short content has two tiers`() {
        let short = Duration.seconds(20 * 60)
        #expect(SeekAcceleration.multiplier(repeatCount: 89, duration: short) == 1)
        #expect(SeekAcceleration.multiplier(repeatCount: 90, duration: short) == 2)
    }

    @Test func `medium content escalates across all tiers`() {
        let medium = Duration.seconds(60 * 60)
        #expect(SeekAcceleration.multiplier(repeatCount: 38, duration: medium) == 1)
        #expect(SeekAcceleration.multiplier(repeatCount: 39, duration: medium) == 2)
        #expect(SeekAcceleration.multiplier(repeatCount: 150, duration: medium) == 3)
        #expect(SeekAcceleration.multiplier(repeatCount: 225, duration: medium) == 4)
    }

    @Test func `feature-length and longer content speed up further`() {
        let movie = Duration.seconds(93 * 60)
        #expect(SeekAcceleration.multiplier(repeatCount: 59, duration: movie) == 1)
        #expect(SeekAcceleration.multiplier(repeatCount: 60, duration: movie) == 2)
        #expect(SeekAcceleration.multiplier(repeatCount: 120, duration: movie) == 4)
        #expect(SeekAcceleration.multiplier(repeatCount: 180, duration: movie) == 6)
        let long = Duration.seconds(3 * 60 * 60)
        #expect(SeekAcceleration.multiplier(repeatCount: 60, duration: long) == 3)
        #expect(SeekAcceleration.multiplier(repeatCount: 120, duration: long) == 6)
        #expect(SeekAcceleration.multiplier(repeatCount: 180, duration: long) == 10)
    }

    @Test func `with the controls hidden, the first repeats pass and letting go seeks once`() {
        var press = HeldSeekPress(.forward, ignoredRepeats: SeekAcceleration.hiddenControlsIgnoredRepeats)
        for _ in 1 ..< 8 {
            #expect(press.repeated(duration: .seconds(5400)) == nil)
        }
        #expect(press.stepsOnRelease == 1)

        #expect(press.repeated(duration: .seconds(5400)) == 1)
        #expect(press.stepsOnRelease == 0)
    }

    @Test func `on the seek bar every repeat seeks`() {
        var press = HeldSeekPress(.back, ignoredRepeats: 0)
        #expect(press.stepsOnRelease == 1)
        #expect(press.repeated(duration: .seconds(5400)) == 1)
        #expect(press.stepsOnRelease == 0)
        for _ in 2 ..< 60 {
            _ = press.repeated(duration: .seconds(5400))
        }
        #expect(press.repeated(duration: .seconds(5400)) == 2)
    }

    @Test func `a swipe across the surface seeks a fifth of the video, within limits`() {
        #expect(SwipeScrubbing.span(for: .seconds(93 * 60)) == .seconds(600))
        #expect(SwipeScrubbing.span(for: .seconds(20 * 60)) == .seconds(240))
        #expect(SwipeScrubbing.span(for: .seconds(5 * 60)) == .seconds(120))
        #expect(SwipeScrubbing.span(for: nil) == .seconds(120))
        #expect(SwipeScrubbing.offset(translation: -480, width: 1920, duration: .seconds(20 * 60)) == .seconds(-60))
        #expect(SwipeScrubbing.offset(translation: 100, width: 0, duration: .seconds(600)) == .zero)
    }
}
