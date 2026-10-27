import AnemoneCore

/// How loud theme music plays on item pages, Wholphin's `ThemeSongVolume`.
public enum ThemeMusicVolume: String, CaseIterable, PreferenceValue, Sendable {
    case disabled
    case lowest
    case low
    case medium
    case high
    case highest

    /// The player's volume, from 0 to 1; `nil` when theme music is off. Wholphin's "highest" is
    /// `75f`, a slip for `.75f` (`ThemeSongPlayer.kt:88`) that asks ExoPlayer for 75 times full
    /// volume; it's 0.75 here.
    public var level: Float? {
        switch self {
        case .disabled: nil
        case .lowest: 0.05
        case .low: 0.1
        case .medium: 0.25
        case .high: 0.5
        case .highest: 0.75
        }
    }
}

public extension Preferences {
    /// Wholphin's "Play theme music" (`playThemeSongs`), medium by default.
    static let playThemeSongs = Preference("playThemeSongs", default: ThemeMusicVolume.medium)
}
