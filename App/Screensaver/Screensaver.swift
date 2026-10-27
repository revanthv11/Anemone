import AnemoneCore
import Foundation
import Observation

/// The in-app screensaver's timer, ported from Wholphin's `ScreensaverService`: it shows once
/// the remote has been left alone for the delay chosen in Settings › Screensaver, while it's
/// turned on and nothing keeps the screen on (`keepsScreenOn`, such as a video playing). Any
/// press or touch closes it. tvOS has no screensaver API for apps, so this is all in the app,
/// and the system's own screensaver still takes over later.
@Observable
final class Screensaver {
    private(set) var isShowing = false
    /// Whether something on screen keeps the screen on, which pauses the timer like Wholphin's
    /// `keepScreenOn`. The presenter sets it.
    @ObservationIgnored var keepsScreenOn: () -> Bool = { false }
    @ObservationIgnored private var schedule = ScreensaverSchedule(startDelay: .seconds(900), now: .now)

    /// Turned on in Settings, or by the DEBUG launch argument.
    var isEnabled: Bool {
        Self.debugStartDelay != nil || Preferences.screensaverEnabled.value()
    }

    /// A press or touch on the remote: the wait starts again.
    func noteActivity() {
        schedule.noteActivity(at: .now)
    }

    /// Shows it now, even when it's turned off, like Wholphin's "Start screensaver".
    func start() {
        isShowing = true
    }

    func stop() {
        isShowing = false
        noteActivity()
    }

    /// Runs the timer until the calling task is cancelled.
    func run() async {
        noteActivity()
        while !Task.isCancelled {
            schedule.startDelay = Self.debugStartDelay ?? .seconds(Preferences.screensaverStartDelay.value())
            let decision: ScreensaverSchedule.Decision
            if isShowing || !isEnabled {
                // Checked again later, in case it's turned on meanwhile.
                schedule.noteActivity(at: .now)
                decision = .wait(until: .now + ScreensaverSchedule.pollInterval)
            } else {
                decision = schedule.check(at: .now, keepsScreenOn: keepsScreenOn())
            }
            switch decision {
            case .start:
                isShowing = true
            case let .wait(until):
                try? await Task.sleep(until: until, clock: .continuous)
            }
        }
    }

    /// Launched with `-screensaverIdleSeconds <n>`, DEBUG builds turn the screensaver on with an
    /// n-second delay, for testing. Release builds ignore it.
    static var debugStartDelay: Duration? {
        #if DEBUG
            let seconds = UserDefaults.standard.integer(forKey: "screensaverIdleSeconds")
            return seconds > 0 ? .seconds(seconds) : nil
        #else
            return nil
        #endif
    }
}
