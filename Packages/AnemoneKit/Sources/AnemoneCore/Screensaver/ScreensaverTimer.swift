import Foundation
import Observation

/// The in-app screensaver's timer, ported from Wholphin's `ScreensaverService`: it shows once
/// the remote has been left alone for the delay chosen in Settings › Screensaver, while it's
/// turned on and nothing keeps the screen on (`keepsScreenOn`, such as a video playing). Any
/// press or touch closes it. tvOS has no screensaver API for apps, so this is all in the app,
/// and the system's own screensaver still takes over later.
///
/// `isShowing` is what should be on screen; the app's presenter shows it and says whether it
/// really is (`isOnScreen`), so a screensaver that never made it on screen, or that the system
/// took off screen without `stop()`, doesn't count as showing for long.
@MainActor
@Observable
public final class ScreensaverTimer {
    /// What the timer follows, read each time it looks.
    public struct Settings: Equatable, Sendable {
        public var isEnabled: Bool
        public var startDelay: Duration

        public init(isEnabled: Bool, startDelay: Duration) {
            self.isEnabled = isEnabled
            self.startDelay = startDelay
        }
    }

    public private(set) var isShowing = false
    /// Whether something on screen keeps the screen on, which pauses the timer like Wholphin's
    /// `keepScreenOn`. The presenter sets it.
    @ObservationIgnored public var keepsScreenOn: () -> Bool = { false }
    /// Whether the screensaver is on screen. The presenter sets it.
    @ObservationIgnored public var isOnScreen: () -> Bool = { true }
    @ObservationIgnored private let settings: () -> Settings
    @ObservationIgnored private let pollInterval: Duration
    @ObservationIgnored private var schedule: ScreensaverSchedule
    /// The wait under way, which `stop()` cuts short.
    @ObservationIgnored private var nap: Task<Void, Never>?

    /// - Parameter pollInterval: how often to look again while waiting or showing.
    public init(pollInterval: Duration = ScreensaverSchedule.pollInterval, settings: @escaping () -> Settings) {
        self.pollInterval = pollInterval
        self.settings = settings
        schedule = ScreensaverSchedule(startDelay: settings().startDelay, now: .now)
    }

    /// A press or touch on the remote: the wait starts again.
    public func noteActivity() {
        schedule.noteActivity(at: .now)
    }

    /// Shows it now, even when it's turned off, like Wholphin's "Start screensaver".
    public func start() {
        isShowing = true
    }

    /// Closes it, or notes that it went: the wait starts again from now, and the timer looks
    /// again at once rather than at its next poll, so a short delay is kept to.
    public func stop() {
        isShowing = false
        noteActivity()
        nap?.cancel()
    }

    /// Runs the timer until the calling task is cancelled.
    public func run() async {
        noteActivity()
        while !Task.isCancelled {
            if isShowing {
                await wait(until: .now + pollInterval)
                // Gone without `stop()`: it never made it on screen, or the system took it away
                // with what it was shown over. It can show again after the delay.
                if isShowing, !Task.isCancelled, !isOnScreen() {
                    stop()
                }
                continue
            }
            let current = settings()
            schedule.startDelay = current.startDelay
            guard current.isEnabled else {
                // Checked again later, in case it's turned on meanwhile.
                schedule.noteActivity(at: .now)
                await wait(until: .now + pollInterval)
                continue
            }
            switch schedule.check(at: .now, keepsScreenOn: keepsScreenOn()) {
            case .start:
                isShowing = true
            case let .wait(until):
                await wait(until: min(until, .now + pollInterval))
            }
        }
    }

    /// Sleeps until `deadline`, or until `stop()` or the calling task's cancellation.
    private func wait(until deadline: ContinuousClock.Instant) async {
        let nap = Task<Void, Never> {
            try? await Task.sleep(until: deadline, clock: .continuous)
        }
        self.nap = nap
        await withTaskCancellationHandler {
            await nap.value
        } onCancel: {
            nap.cancel()
        }
        if self.nap == nap {
            self.nap = nil
        }
    }
}
