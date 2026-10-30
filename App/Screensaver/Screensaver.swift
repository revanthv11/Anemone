import AnemoneCore
import Foundation
import Observation

/// The in-app screensaver: its timer (`ScreensaverTimer`, ported from Wholphin's
/// `ScreensaverService`) with the settings from Settings › Screensaver. It shows once the remote
/// has been left alone for the chosen delay, while it's turned on and nothing keeps the screen
/// on, such as a video playing. Any press or touch closes it. With "Dim screen after delay", the
/// screen dims after the same delay, with the screensaver's pictures or without them.
@Observable
final class Screensaver {
    @ObservationIgnored private let timer = ScreensaverTimer {
        ScreensaverTimer.Settings(
            isEnabled: Preferences.screensaverEnabled.value() || Screensaver.debugTurnsOn,
            startDelay: Screensaver.debugStartDelay ?? .seconds(Preferences.screensaverStartDelay.value()),
            dimsScreen: Preferences.screensaverDimEnabled.value(),
        )
    }

    /// Whether `-screensaverIdleSeconds` turns the screensaver on: it does unless the launch also
    /// says `-screensaverEnabled NO`, so the dimming can be tried on its own. Only the launch's
    /// arguments count, so a setting stored on the device doesn't turn the flag off.
    private static var debugTurnsOn: Bool {
        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        return debugStartDelay != nil && arguments[Preferences.screensaverEnabled.key] == nil
    }

    /// Whether it should be on screen. The presenter shows it, and closes it when this goes.
    var isShowing: Bool {
        timer.isShowing
    }

    /// While showing: the screensaver's pictures, or only the dimming.
    var showsSlides: Bool {
        timer.showsSlides
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
