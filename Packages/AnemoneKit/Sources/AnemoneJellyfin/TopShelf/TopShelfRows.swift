import Foundation

/// A row of the Top Shelf, which tvOS shows above Anemone when it's in the top row of the home
/// screen. It plays the part of the Watch Next row Wholphin's `TvProviderWorker` fills on
/// Android TV, as two sections.
public struct TopShelfRow: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case continueWatching
        case nextUp
    }

    public let kind: Kind
    public let items: [MediaItem]

    public init(kind: Kind, items: [MediaItem]) {
        self.kind = kind
        self.items = items
    }

    public var title: String {
        switch kind {
        case .continueWatching: String(localized: "Continue Watching", bundle: .module)
        case .nextUp: String(localized: "Next Up", bundle: .module)
        }
    }
}

/// The Next Up settings the Top Shelf follows, which the app leaves for it in the App Group.
public struct TopShelfOptions: Hashable, Sendable {
    /// Wholphin's Watch Next row asks for 10 of each.
    public var limit: Int
    public var enableRewatchingNextUp: Bool
    public var maxDaysNextUp: Int

    public init(limit: Int = 10, enableRewatchingNextUp: Bool = false, maxDaysNextUp: Int = -1) {
        self.limit = limit
        self.enableRewatchingNextUp = enableRewatchingNextUp
        self.maxDaysNextUp = maxDaysNextUp
    }
}

public extension TopShelfOptions {
    /// What the app last left in `defaults` (the App Group's), or the defaults when nothing.
    init(defaults: UserDefaults) {
        self.init(
            enableRewatchingNextUp: defaults.bool(forKey: Keys.enableRewatchingNextUp),
            maxDaysNextUp: defaults.object(forKey: Keys.maxDaysNextUp) as? Int ?? -1,
        )
    }

    /// Leaves the Next Up settings for the Top Shelf. The limit is the Top Shelf's own.
    func write(to defaults: UserDefaults) {
        defaults.set(enableRewatchingNextUp, forKey: Keys.enableRewatchingNextUp)
        defaults.set(maxDaysNextUp, forKey: Keys.maxDaysNextUp)
    }

    private enum Keys {
        static let enableRewatchingNextUp = "topShelf.enableRewatchingNextUp"
        static let maxDaysNextUp = "topShelf.maxDaysNextUp"
    }
}

public extension JellyfinSession {
    /// Continue Watching, then Next Up, as Wholphin's `TvProviderWorker.getPotentialItems` picks
    /// them: Next Up keeps only episodes of a series, leaving out the series already in Continue
    /// Watching, and the series taken out of Next Up, like Home's row. Read-only: nothing on the
    /// server changes. Empty rows are left out.
    ///
    /// - Throws: `SessionError.signedOut` when the token was revoked, or when either row fails.
    func topShelfRows(options: TopShelfOptions = TopShelfOptions(), now: Date = .now) async throws -> [TopShelfRow] {
        let homeOptions = HomeOptions(
            itemsPerRow: options.limit,
            enableRewatchingNextUp: options.enableRewatchingNextUp,
            maxDaysNextUp: options.maxDaysNextUp,
        )
        // All three at once: the series taken out of Next Up are left out after it's fetched,
        // rather than Next Up waiting for them.
        let everySeries = HomeRowContext(libraries: [], options: homeOptions, removed: RemovedFromNextUp())
        async let removedResult = attempt { try await removedFromNextUp() }
        async let resumeResult = resumeEntries(limit: options.limit)
        async let nextUpResult = nextUpEntries(context: everySeries, now: now)

        let resume = try await resumeResult.map(\.item)
        let nextUpFound = try await nextUpResult
        // A failed read shows every series, as if none were removed, as on Home.
        let removed = await (try? removedResult.get()) ?? RemovedFromNextUp()
        let inProgress = Set(resume.compactMap(\.episode?.seriesID))
        let nextUp = nextUpFound.filter { entry in
            guard let seriesID = entry.item.episode?.seriesID else { return false }
            return !inProgress.contains(seriesID) && removed.allows(seriesID: seriesID, lastPlayed: entry.lastPlayed)
        }
        .map(\.item)
        return [
            TopShelfRow(kind: .continueWatching, items: resume),
            TopShelfRow(kind: .nextUp, items: nextUp),
        ]
        .filter { !$0.items.isEmpty }
    }
}
