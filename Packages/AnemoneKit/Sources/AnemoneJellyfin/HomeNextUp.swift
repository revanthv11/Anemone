import AnemoneCore
import Foundation
import JellyfinAPI

/// The series the user took out of Next Up, and when. Ported from Wholphin's `RemovedSeriesIds`,
/// kept in the same JSON under `removeNextUp`: `{"value":{"<series id>":"<local date-time>"}}`.
public struct RemovedFromNextUp: Hashable, Sendable {
    /// By series ID, in the compact form.
    public var dates: [String: Date]

    public init(dates: [String: Date] = [:]) {
        self.dates = dates
    }

    /// Reads Wholphin's JSON. Entries it can't read are dropped.
    public init(json: String) throws {
        let decoded = try JSONDecoder().decode([String: [String: String]].self, from: Data(json.utf8))
        let entries = (decoded["value"] ?? [:]).compactMap { id, date in
            Self.date(from: date).map { (JellyfinID.compact(id), $0) }
        }
        dates = Dictionary(entries) { first, _ in first }
    }

    public func json() throws -> String {
        let value = Dictionary(uniqueKeysWithValues: dates
            .map { (JellyfinID.dashed($0.key), Self.text(for: $0.value)) })
        let data = try JSONEncoder().encode(["value": value])
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    /// Whether Next Up may show an episode: not if its series was removed, unless the episode was
    /// played since. An episode whose last play is unknown stays hidden, as in Wholphin.
    func allows(seriesID: String?, lastPlayed: Date?) -> Bool {
        guard let seriesID, let removed = dates[JellyfinID.compact(seriesID)] else { return true }
        guard let lastPlayed else { return false }
        return lastPlayed > removed
    }

    // Wholphin writes Java's ISO_LOCAL_DATE_TIME: the device's wall-clock time with no zone.

    static func date(from text: String) -> Date? {
        if let date = try? Date(text, strategy: .iso8601) {
            return date
        }
        let parts = text.split(separator: ".", maxSplits: 1)
        guard let whole = parts.first, let seconds = localFormatter.date(from: String(whole)) else { return nil }
        let fraction = parts.count > 1 ? Double("0.\(parts[1].prefix { $0.isNumber })") ?? 0 : 0
        return seconds.addingTimeInterval(fraction)
    }

    static func text(for date: Date) -> String {
        let seconds = date.timeIntervalSince1970.rounded(.down)
        let millis = Int(((date.timeIntervalSince1970 - seconds) * 1000).rounded(.down))
        let whole = localFormatter.string(from: Date(timeIntervalSince1970: seconds))
        return whole + "." + String(format: "%03d", millis)
    }

    /// A new one each time: they're seldom needed, and the current time zone can change.
    private static var localFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }
}

public extension JellyfinSession {
    /// The series taken out of Next Up, from Anemone's DisplayPreferences entry.
    func removedFromNextUp() async throws -> RemovedFromNextUp {
        let prefs = try await customPrefs(client: HomeDisplayPreferences.anemoneClient)
        return try prefs[HomeDisplayPreferences.removedNextUpKey].map(RemovedFromNextUp.init(json:))
            ?? RemovedFromNextUp()
    }
}

public extension HomePreferencesWriter {
    /// Takes an episode's series out of Next Up until the user plays one of its episodes, as
    /// Wholphin's `removeFromNextUp` does: the episode is marked unwatched, which clears its last
    /// play, and the series is noted with the time.
    func removeFromNextUp(_ episode: MediaItem, session: JellyfinSession, now: Date = .now) async throws {
        guard let seriesID = episode.episode?.seriesID else { return }
        try await session.setPlayed(false, itemID: episode.id)
        try await updateRemoved { $0.dates[JellyfinID.compact(seriesID)] = now }
    }

    /// Lets Next Up show a removed series again.
    func allowInNextUp(seriesID: String) async throws {
        try await updateRemoved { $0.dates[JellyfinID.compact(seriesID)] = nil }
    }

    private func updateRemoved(_ change: @escaping @Sendable (inout RemovedFromNextUp) -> Void) async throws {
        try await update { prefs in
            let key = HomeDisplayPreferences.removedNextUpKey
            var removed = try prefs[key].map(RemovedFromNextUp.init(json:)) ?? RemovedFromNextUp()
            change(&removed)
            prefs[key] = try removed.json()
        }
    }
}

/// An item on a watching row, with what ordering the combined row needs.
struct WatchingEntry: Sendable {
    let item: MediaItem
    let lastPlayed: Date?
    let premiereDate: Date?

    init?(_ dto: BaseItemDto) {
        guard let item = MediaItem(dto) else { return nil }
        self.item = item
        lastPlayed = dto.userData?.lastPlayedDate
        premiereDate = dto.premiereDate
    }
}

extension JellyfinSession {
    /// Wholphin's `buildCombined`: Continue Watching and Next Up together, most recent first. A
    /// next episode counts as played when the one before it was, or when it came out, whichever
    /// is later, so a new episode of a show the user keeps up with comes near the front.
    func combinedWatching(
        resume: [WatchingEntry],
        nextUp: [WatchingEntry],
        cache: HomeCache,
    ) async -> [MediaItem] {
        // Three at a time, as in Wholphin.
        let nextUpDates = await boundedMap(nextUp.count, width: 3) { index in
            await logicalLastPlayed(of: nextUp[index], cache: cache)
        }
        let dated = resume.map { ($0.item, $0.lastPlayed) } + zip(nextUp.map(\.item), nextUpDates).map { ($0, $1) }
        // Stable, newest first, unknown dates last.
        return dated.enumerated()
            .sorted { lhs, rhs in
                let left = lhs.element.1 ?? .distantPast
                let right = rhs.element.1 ?? .distantPast
                return left != right ? left > right : lhs.offset < rhs.offset
            }
            .map(\.element.0)
    }

    /// Wholphin's `DatePlayedService.getLastPlayed`: when the episode before this one was last
    /// played, or this one's premiere if later. Kept for two hours.
    private func logicalLastPlayed(of entry: WatchingEntry, cache: HomeCache) async -> Date? {
        guard let seriesID = entry.item.episode?.seriesID else { return nil }
        let key = "\(seriesID)/\(entry.item.id)"
        if let cached = await cache.datePlayed(for: key) {
            return cached
        }
        let premiere = entry.premiereDate ?? .distantPast
        let date: Date
        do {
            let parameters = Paths.GetEpisodesParameters(userID: userID, adjacentTo: entry.item.id, limit: 1)
            let previous = try await send(Paths.getEpisodes(seriesID: seriesID, parameters: parameters)).items?.first
            date = max(previous?.userData?.lastPlayedDate ?? .distantPast, premiere)
        } catch is CancellationError {
            return nil
        } catch {
            return premiere
        }
        await cache.setDatePlayed(date, for: key)
        return date
    }
}
