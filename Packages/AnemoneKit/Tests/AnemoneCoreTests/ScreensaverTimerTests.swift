@testable import AnemoneCore
import Foundation
import Testing

/// The screensaver's timer loop (`ScreensaverTimer`), with short delays. Each test waits for a
/// state with a generous deadline, well under the poll interval the timer would otherwise sleep
/// through.
@MainActor
struct ScreensaverTimerTests {
    @Test func `starts once the remote is left alone for the delay`() async {
        let timer = ScreensaverTimer(pollInterval: .seconds(60)) {
            .init(isEnabled: true, startDelay: .milliseconds(200))
        }
        let running = Task { await timer.run() }
        defer { running.cancel() }

        #expect(await showing(timer, is: true, within: .seconds(5)))
    }

    @Test func `stop wakes the timer, so it starts again after the delay rather than the next poll`() async {
        let timer = ScreensaverTimer(pollInterval: .seconds(60)) {
            .init(isEnabled: true, startDelay: .milliseconds(200))
        }
        let running = Task { await timer.run() }
        defer { running.cancel() }
        #expect(await showing(timer, is: true, within: .seconds(5)))

        // A press closes it. Without waking up, the timer would sleep through its 60 s poll.
        timer.stop()

        #expect(!timer.isShowing)
        #expect(await showing(timer, is: true, within: .seconds(5)))
    }

    @Test func `a screensaver that isn't on screen stops counting as showing`() async {
        let timer = ScreensaverTimer(pollInterval: .milliseconds(200)) {
            .init(isEnabled: true, startDelay: .seconds(60))
        }
        // It never made it on screen, or the system took it away without a press.
        timer.isOnScreen = { false }
        let running = Task { await timer.run() }
        defer { running.cancel() }

        timer.start()

        #expect(await showing(timer, is: false, within: .seconds(5)))
    }

    @Test func `a screensaver on screen keeps showing`() async throws {
        let timer = ScreensaverTimer(pollInterval: .milliseconds(100)) {
            .init(isEnabled: true, startDelay: .seconds(60))
        }
        timer.isOnScreen = { true }
        let running = Task { await timer.run() }
        defer { running.cancel() }

        timer.start()
        try await Task.sleep(for: .milliseconds(500))

        #expect(timer.isShowing)
    }

    @Test func `turned off, it doesn't start`() async throws {
        let timer = ScreensaverTimer(pollInterval: .milliseconds(100)) {
            .init(isEnabled: false, startDelay: .milliseconds(50))
        }
        let running = Task { await timer.run() }
        defer { running.cancel() }

        try await Task.sleep(for: .milliseconds(500))

        #expect(!timer.isShowing)
    }

    @Test func `cancelling the run ends it while it waits`() async {
        let timer = ScreensaverTimer(pollInterval: .seconds(60)) {
            .init(isEnabled: false, startDelay: .seconds(60))
        }
        let running = Task { await timer.run() }
        try? await Task.sleep(for: .milliseconds(100))
        let start = ContinuousClock.now

        running.cancel()
        await running.value

        #expect(ContinuousClock.now - start < .seconds(5))
    }

    /// Whether `timer.isShowing` becomes `expected` before `timeout`.
    private func showing(_ timer: ScreensaverTimer, is expected: Bool, within timeout: Duration) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if timer.isShowing == expected {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return timer.isShowing == expected
    }
}
