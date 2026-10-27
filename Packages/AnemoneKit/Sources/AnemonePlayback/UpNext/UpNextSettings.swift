import AnemoneCore
import Foundation

/// When Up Next appears, Wholphin's `ShowNextUpWhen` without "Never".
public enum UpNextTiming: String, CaseIterable, Sendable, PreferenceValue {
    /// When the entry has played to the end, Wholphin's default.
    case endOfPlayback
    /// When the credits start, as the media segments feature finds them; at the end when an
    /// entry has none.
    case duringCredits
}

/// Settings › Playback › Autoplay, with Wholphin's names and defaults where Wholphin has them.
public extension Preferences {
    /// Wholphin's `autoPlayNext`: whether Up Next counts down and plays the next entry.
    static let autoPlayNext = Preference("autoPlayNext", default: true)
    /// Wholphin's `autoPlayNextDelaySeconds`: how long Up Next counts down; 0 plays at once.
    static let autoPlayNextDelaySeconds = Preference("autoPlayNextDelaySeconds", default: 15)
    /// Wholphin's `showNextUpWhen`.
    static let showNextUpWhen = Preference("showNextUpWhen", default: UpNextTiming.endOfPlayback)
    /// How many entries may play on their own in a row, with no press on the remote, before the
    /// player asks "Still watching?"; 0 never asks. Wholphin counts hours since the last press
    /// instead (2 by default); 3 episodes is about that long for an hour-long series.
    static let passOutProtectionCount = Preference("passOutProtectionCount", default: 3)
}

public extension UpNext {
    /// What Up Next does, from the user's settings.
    struct Settings: Sendable {
        public var autoplays: Bool
        public var countdown: Duration
        public var timing: UpNextTiming
        /// See `Preferences.passOutProtectionCount`.
        public var passOutCount: Int
        /// How long "Still watching?" waits for an answer before playback stops.
        public var stillWatchingTimeout: Duration
        /// For live checks only: where to act as if the credits start in every entry, from the
        /// `-upNextCreditsAt <seconds>` launch argument in debug builds.
        public var testCreditsStart: Duration?

        public init(
            autoplays: Bool = true,
            countdown: Duration = .seconds(15),
            timing: UpNextTiming = .endOfPlayback,
            passOutCount: Int = 3,
            stillWatchingTimeout: Duration = .seconds(60),
            testCreditsStart: Duration? = nil,
        ) {
            self.autoplays = autoplays
            self.countdown = countdown
            self.timing = timing
            self.passOutCount = passOutCount
            self.stillWatchingTimeout = stillWatchingTimeout
            self.testCreditsStart = testCreditsStart
        }

        /// The user's settings now.
        public static func current(in defaults: UserDefaults = .standard) -> Self {
            Self(
                autoplays: Preferences.autoPlayNext.value(in: defaults),
                countdown: .seconds(max(0, Preferences.autoPlayNextDelaySeconds.value(in: defaults))),
                timing: Preferences.showNextUpWhen.value(in: defaults),
                passOutCount: max(0, Preferences.passOutProtectionCount.value(in: defaults)),
                testCreditsStart: testCreditsStart(in: defaults),
            )
        }

        private static func testCreditsStart(in defaults: UserDefaults) -> Duration? {
            #if DEBUG
                let seconds = defaults.integer(forKey: "upNextCreditsAt")
                return seconds > 0 ? .seconds(seconds) : nil
            #else
                return nil
            #endif
        }
    }
}
