import AnemoneCore

/// Settings › Screensaver, with Wholphin's defaults (`ScreensaverPreference`).
extension Preferences {
    /// "Use in-app screensaver". Off, as in Wholphin.
    static let screensaverEnabled = Preference("screensaverEnabled", default: false)
    /// "Start after", in seconds.
    static let screensaverStartDelay = Preference("screensaverStartDelay", default: 15 * 60)
    /// "Duration": how long each picture shows, in seconds.
    static let screensaverDuration = Preference("screensaverDuration", default: 30)
    /// "Show clock".
    static let screensaverShowClock = Preference("screensaverShowClock", default: true)
    /// "Animate": each picture slowly zooms in and out.
    static let screensaverAnimate = Preference("screensaverAnimate", default: true)
    /// "Max age rating", in years; -1 for no limit.
    static let screensaverMaxAge = Preference("screensaverMaxAge", default: 16)
}

/// Wholphin's choices for each setting.
enum ScreensaverChoices {
    static let startDelays = [30, 60, 120, 300, 600, 900, 1800, 3600]
    static let durations = [15, 30, 60, 120]
    static let maxAges = [0, 5, 10, 13, 14, 16, 18, 21, -1]
}
