import AnemoneCore
import Foundation
import Observation

/// The in-app screensaver: its timer (`ScreensaverTimer`, ported from Wholphin's
/// `ScreensaverService`) with the settings from Settings › Screensaver. It shows once the remote
/// has been left alone for the chosen delay, while it's turned on and nothing keeps the screen
/// on, such as a video playing. Any press or touch closes it.
@Observable
final class Screensaver {
    @ObservationIgnored private let timer = ScreensaverTimer {
        ScreensaverTimer.Settings(
            isEnabled: Screensaver.debugStartDelay != nil || Preferences.screensaverEnabled.value(),
            startDelay: Screensaver.debugStartDelay ?? .seconds(Preferences.screensaverStartDelay.value()),
        )
    }

    /// Whether it should be on screen. The presenter shows it, and closes it when this goes.
    var isShowing: Bool {
        timer.isShowing
    }

    /// Whether something on screen keeps the screen on, which pauses the timer like Wholphin's
    /// `keepScreenOn`. The presenter sets it.
    var keepsScreenOn: () -> Bool {
        get { timer.keepsScreenOn }
        set { timer.keepsScreenOn = newValue }
    }

    /// Whether the screensaver is really on screen. The presenter sets it.
    var isOnScreen: () -> Bool {
        get { timer.isOnScreen }
        set { timer.isOnScreen = newValue }
    }

    /// A press or touch on the remote: the wait starts again.
    func noteActivity() {
        timer.noteActivity()
    }

    /// Shows it now, even when it's turned off, like Wholphin's "Start screensaver".
    func start() {
        timer.start()
    }

    /// Closes it, or notes that it went: the wait starts again.
    func stop() {
        timer.stop()
    }

    /// Runs the timer until the calling task is cancelled.
    func run() async {
        await timer.run()
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
