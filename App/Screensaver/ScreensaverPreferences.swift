import AnemoneCore
import AnemoneJellyfin

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
    /// "Include types": which items' pictures show. Movies and shows, as in Wholphin.
    static let screensaverItemTypes = Preference("screensaverItemTypes", default: ScreensaverItemTypes.default)
    /// "Dim screen after delay": whether the screen dims after "Start after", with or without the
    /// screensaver. Off, as Wholphin's stored setting starts.
    static let screensaverDimEnabled = Preference("screensaverDimEnabled", default: false)
    /// "Dim percentage": how dark, from 0 to 95.
    static let screensaverDimPercent = Preference("screensaverDimPercent", default: 75)
}

/// Wholphin's choices for each setting.
enum ScreensaverChoices {
    static let startDelays = [30, 60, 120, 300, 600, 900, 1800, 3600]
    static let durations = [15, 30, 60, 120]
    static let maxAges = [0, 5, 10, 13, 14, 16, 18, 21, -1]
    /// Wholphin's slider: 0 to 95 in steps of 5.
    static let dimPercents = Array(stride(from: 0, through: 95, by: 5))
}
