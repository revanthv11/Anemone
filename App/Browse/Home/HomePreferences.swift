import AnemoneCore

/// Settings › Home's settings for every row, with Wholphin's names and defaults
/// (`HomePagePreferences`).
extension Preferences {
    /// "Max items on home page rows", 5 to 50.
    static let maxItemsPerRow = Preference("maxItemsPerRow", default: 25)
    /// "Enable rewatching in next up".
    static let enableRewatchingNextUp = Preference("enableRewatchingNextUp", default: false)
    /// "Max days in Next Up": how long ago a series was watched for its next episode to show; -1
    /// for no limit.
    static let maxDaysNextUp = Preference("maxDaysNextUp", default: -1)
}

enum HomePreferenceChoices {
    static let itemsPerRow = [5, 10, 15, 20, 25, 30, 40, 50]
    /// Wholphin's `MaxDaysNextUpOptions`, then no limit.
    static let maxDaysNextUp = [7, 14, 30, 60, 90, 180, 365, -1]
}
