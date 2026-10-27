import AnemoneCore
import Testing

struct ScreensaverScheduleTests {
    private let start = ContinuousClock.now

    @Test func `starts once the remote is left alone for the delay`() {
        var schedule = ScreensaverSchedule(startDelay: .seconds(60), now: start)

        #expect(schedule.check(at: start + .seconds(20), keepsScreenOn: false)
            == .wait(until: start + .seconds(50)))
        #expect(schedule.check(at: start + .seconds(50), keepsScreenOn: false)
            == .wait(until: start + .seconds(60)))
        #expect(schedule.check(at: start + .seconds(60), keepsScreenOn: false) == .start)
    }

    @Test func `a press starts the wait again`() {
        var schedule = ScreensaverSchedule(startDelay: .seconds(10), now: start)

        schedule.noteActivity(at: start + .seconds(8))

        #expect(schedule.check(at: start + .seconds(12), keepsScreenOn: false)
            == .wait(until: start + .seconds(18)))
        #expect(schedule.check(at: start + .seconds(18), keepsScreenOn: false) == .start)
    }

    @Test func `playback keeps it away, and the wait starts again when playback ends`() {
        var schedule = ScreensaverSchedule(startDelay: .seconds(10), now: start)

        // Still playing when the delay is up.
        #expect(schedule.check(at: start + .seconds(15), keepsScreenOn: true)
            == .wait(until: start + .seconds(25)))
        #expect(schedule.lastActivity == start + .seconds(15))
        #expect(schedule.check(at: start + .seconds(24), keepsScreenOn: false)
            == .wait(until: start + .seconds(25)))
        #expect(schedule.check(at: start + .seconds(25), keepsScreenOn: false) == .start)
    }

    @Test func `long delays are checked at least every 30 seconds`() {
        var schedule = ScreensaverSchedule(startDelay: .seconds(15 * 60), now: start)

        #expect(schedule.check(at: start, keepsScreenOn: false) == .wait(until: start + .seconds(30)))
    }
}
