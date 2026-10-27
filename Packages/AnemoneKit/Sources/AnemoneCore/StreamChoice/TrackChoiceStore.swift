import Foundation

/// Remembers one user's track choices: per item, and per season and series for episodes.
/// Wholphin keeps these in its database; a tvOS app has little room outside UserDefaults, so
/// this keeps only the most recent ones, as one small JSON value per user.
public struct TrackChoiceStore {
    /// How many items' and seasons' or series' choices are kept, most recent first. A few dozen
    /// kilobytes at most.
    public static let itemLimit = 200
    public static let seriesLimit = 100

    private let key: String
    private let defaults: UserDefaults

    public init(userID: String, defaults: UserDefaults = .standard) {
        key = "trackChoices.\(userID)"
        self.defaults = defaults
    }

    public func itemChoice(for itemID: String) -> ItemTrackChoice? {
        stored.items.last { $0.itemID == itemID }
    }

    public func save(_ choice: ItemTrackChoice) {
        update { stored in
            stored.items.removeAll { $0.itemID == choice.itemID }
            stored.items.append(choice)
            stored.items = Array(stored.items.suffix(Self.itemLimit))
        }
    }

    /// The choices kept for an episode's season and series, the season's first, as Wholphin's
    /// query orders them.
    public func seriesChoices(_ kind: MediaTrack.Kind, seriesID: String?, seasonID: String?) -> [SeriesTrackChoice] {
        let choices = stored.series.filter { $0.kind == kind }
        return [seasonID, seriesID].compactMap { parentID in
            parentID.flatMap { id in choices.last { $0.parentID == id } }
        }
    }

    /// Replaces what was kept for the same season or series and kind.
    public func save(_ choice: SeriesTrackChoice) {
        update { stored in
            stored.series.removeAll { $0.parentID == choice.parentID && $0.kind == choice.kind }
            stored.series.append(choice)
            stored.series = Array(stored.series.suffix(Self.seriesLimit))
        }
    }

    /// Forgets every choice, so tracks follow the settings again.
    public func removeAll() {
        defaults.removeObject(forKey: key)
    }

    private struct Stored: Codable {
        /// Oldest first.
        var items: [ItemTrackChoice] = []
        var series: [SeriesTrackChoice] = []
    }

    private var stored: Stored {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Stored.self, from: $0) } ?? Stored()
    }

    private func update(_ change: (inout Stored) -> Void) {
        var stored = stored
        change(&stored)
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: key)
        }
    }
}
