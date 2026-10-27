import Foundation

/// Remembers one user's track choices: per item, and per season and series for episodes.
/// Wholphin keeps these in its database; a tvOS app has little room outside UserDefaults, so
/// this keeps only the most recent ones, as one small JSON value per user.
///
/// The value is decoded once and kept, and written back once per change, since a pick in the
/// player reads and changes it several times. So a store sees changes another store makes only
/// if it's made after them, as each player's is.
public final class TrackChoiceStore {
    /// How many items' and seasons' or series' choices are kept, most recent first. A few dozen
    /// kilobytes at most.
    public static let itemLimit = 200
    public static let seriesLimit = 100

    private let key: String
    private let defaults: UserDefaults
    /// What's stored, once read.
    private var cached: Stored?

    public init(userID: String, defaults: UserDefaults = .standard) {
        key = "trackChoices.\(userID)"
        self.defaults = defaults
    }

    public func itemChoice(for itemID: String) -> ItemTrackChoice? {
        stored.items.last { $0.itemID == itemID }
    }

    /// Saves an item's choice and, for an episode, what to keep for its season and series, in
    /// one write. A season or series choice replaces what was kept for it of the same kind.
    public func save(_ choice: ItemTrackChoice, series: [SeriesTrackChoice] = []) {
        update { stored in
            stored.items.removeAll { $0.itemID == choice.itemID }
            stored.items.append(choice)
            stored.items = Array(stored.items.suffix(Self.itemLimit))
            stored.add(series)
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
        update { $0.add([choice]) }
    }

    /// Forgets every choice, so tracks follow the settings again.
    public func removeAll() {
        cached = Stored()
        defaults.removeObject(forKey: key)
    }

    private struct Stored: Codable {
        /// Oldest first.
        var items: [ItemTrackChoice] = []
        var series: [SeriesTrackChoice] = []

        mutating func add(_ choices: [SeriesTrackChoice]) {
            guard !choices.isEmpty else { return }
            for choice in choices {
                series.removeAll { $0.parentID == choice.parentID && $0.kind == choice.kind }
                series.append(choice)
            }
            series = Array(series.suffix(TrackChoiceStore.seriesLimit))
        }
    }

    private var stored: Stored {
        if let cached {
            return cached
        }
        let stored = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
            ?? Stored()
        cached = stored
        return stored
    }

    private func update(_ change: (inout Stored) -> Void) {
        var stored = stored
        change(&stored)
        cached = stored
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: key)
        }
    }
}
