import AnemoneCore
import AnemoneJellyfin

/// What the player does when it reaches a kind of segment, Wholphin's `SkipSegmentBehavior`.
public enum SkipSegmentBehavior: String, CaseIterable, PreferenceValue, Sendable {
    /// Plays it.
    case ignore
    /// Offers a button to skip it.
    case ask
    /// Jumps past it, once.
    case autoSkip
}

/// Wholphin's settings for each kind of segment, with its names and defaults.
public extension Preferences {
    static let skipIntros = Preference("skipIntros", default: SkipSegmentBehavior.ask)
    static let skipOutros = Preference("skipOutros", default: SkipSegmentBehavior.ask)
    static let skipCommercials = Preference("skipCommercials", default: SkipSegmentBehavior.ask)
    static let skipPreviews = Preference("skipPreviews", default: SkipSegmentBehavior.ignore)
    static let skipRecaps = Preference("skipRecaps", default: SkipSegmentBehavior.ignore)

    static func skipBehavior(for kind: MediaSegment.Kind) -> Preference<SkipSegmentBehavior> {
        switch kind {
        case .intro: skipIntros
        case .outro: skipOutros
        case .commercial: skipCommercials
        case .preview: skipPreviews
        case .recap: skipRecaps
        }
    }
}

public extension MediaSegment.Kind {
    /// The skip button's title, as Wholphin words it.
    var skipTitle: String {
        switch self {
        case .intro: String(localized: "Skip Intro", bundle: .module)
        case .outro: String(localized: "Skip Outro", bundle: .module)
        case .recap: String(localized: "Skip Recap", bundle: .module)
        case .preview: String(localized: "Skip Preview", bundle: .module)
        case .commercial: String(localized: "Skip Ads", bundle: .module)
        }
    }
}
