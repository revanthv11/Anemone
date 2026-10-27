import Foundation

/// When subtitles show for an item the user hasn't chosen any for: Jellyfin's subtitle modes.
public enum SubtitleMode: String, Hashable, Sendable, CaseIterable {
    /// The file's default or forced subtitles.
    case `default`
    /// Subtitles when the audio isn't in the preferred language, otherwise forced ones.
    case smart
    /// Forced subtitles only, such as for signs or lines in another language.
    case onlyForced
    case always
    case none
}

/// The app's subtitle mode setting: Jellyfin's modes, or whatever the user's Jellyfin profile
/// says, which is the default. Wholphin's `SubtitleModePreference`.
public enum SubtitleModeSetting: String, Hashable, Sendable, CaseIterable, PreferenceValue {
    case serverProfile
    case `default`
    case smart
    case onlyForced
    case always
    case none

    public var mode: SubtitleMode? {
        switch self {
        case .serverProfile: nil
        case .default: .default
        case .smart: .smart
        case .onlyForced: .onlyForced
        case .always: .always
        case .none: SubtitleMode.none
        }
    }
}

/// A preferred-language setting. Stored with Wholphin's special values: an empty string for the
/// Jellyfin profile's language and `_any-language` for none in particular.
public enum LanguageSetting: Hashable, Sendable, RawRepresentable, PreferenceValue {
    /// Whatever the user's Jellyfin profile says, which is the default.
    case serverProfile
    case anyLanguage
    /// An ISO 639-2 code, as the server's language list gives it.
    case language(String)

    public init(rawValue: String) {
        self = switch rawValue {
        case "": .serverProfile
        case "_any-language": .anyLanguage
        default: .language(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .serverProfile: ""
        case .anyLanguage: "_any-language"
        case let .language(code): code
        }
    }
}

public extension Preferences {
    static let preferredAudioLanguage = Preference("preferredAudioLanguage", default: LanguageSetting.serverProfile)
    static let preferredSubtitleLanguage = Preference(
        "preferredSubtitleLanguage",
        default: LanguageSetting.serverProfile,
    )
    static let subtitleMode = Preference("subtitleMode", default: SubtitleModeSetting.serverProfile)
}

/// What the user's Jellyfin profile says about audio and subtitles.
public struct ProfileTrackSettings: Hashable, Sendable {
    public var audioLanguage: String?
    public var subtitleLanguage: String?
    public var subtitleMode: SubtitleMode?

    public init(audioLanguage: String? = nil, subtitleLanguage: String? = nil, subtitleMode: SubtitleMode? = nil) {
        self.audioLanguage = audioLanguage
        self.subtitleLanguage = subtitleLanguage
        self.subtitleMode = subtitleMode
    }
}

/// The languages and subtitle mode that choose tracks when nothing was chosen for the item or
/// its series: the app's settings, falling back to the Jellyfin profile's. Wholphin's
/// `getPreferredLanguage` and subtitle-mode lookup.
public struct TrackPreferences: Hashable, Sendable {
    /// `nil` for no preference.
    public var audioLanguage: String?
    public var subtitleLanguage: String?
    public var subtitleMode: SubtitleMode

    public init(audioLanguage: String? = nil, subtitleLanguage: String? = nil, subtitleMode: SubtitleMode = .default) {
        self.audioLanguage = audioLanguage.flatMap(Self.known)
        self.subtitleLanguage = subtitleLanguage.flatMap(Self.known)
        self.subtitleMode = subtitleMode
    }

    public init(
        audio: LanguageSetting,
        subtitle: LanguageSetting,
        mode: SubtitleModeSetting,
        profile: ProfileTrackSettings,
    ) {
        self.init(
            audioLanguage: Self.language(audio, profile: profile.audioLanguage),
            subtitleLanguage: Self.language(subtitle, profile: profile.subtitleLanguage),
            subtitleMode: mode.mode ?? profile.subtitleMode ?? .default,
        )
    }

    /// From the settings in `defaults`, falling back to `profile`.
    public static func current(profile: ProfileTrackSettings, in defaults: UserDefaults = .standard) -> Self {
        Self(
            audio: Preferences.preferredAudioLanguage.value(in: defaults),
            subtitle: Preferences.preferredSubtitleLanguage.value(in: defaults),
            mode: Preferences.subtitleMode.value(in: defaults),
            profile: profile,
        )
    }

    private static func language(_ setting: LanguageSetting, profile: String?) -> String? {
        switch setting {
        case .serverProfile: profile
        case .anyLanguage: nil
        case let .language(code): code
        }
    }

    private static func known(_ code: String) -> String? {
        code.trimmingCharacters(in: .whitespaces).isEmpty ? nil : code
    }
}
