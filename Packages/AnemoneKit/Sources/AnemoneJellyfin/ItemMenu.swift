import Foundation

/// A choice in a card's long-press menu.
public enum ItemMenuEntry: Hashable, Sendable {
    /// Opens the item's page.
    case goTo
    case play
    /// Plays from where the user left off.
    case resume
    /// Plays from the beginning, for an item that could be resumed.
    case restart
    case addToPlaylist
    /// Marks the item unwatched, which takes it out of Continue Watching.
    case removeFromContinueWatching
    case removeFromNextUp
    /// Marks the item watched (`true`) or unwatched (`false`).
    case setPlayed(Bool)
    /// Adds the item to favourites (`true`) or removes it (`false`).
    case setFavorite(Bool)
    case goToSeries(MediaItem)
}

/// The row a card is in, which decides what its menu can take it out of, like Wholphin's
/// `canRemoveContinueWatching` and `canRemoveNextUp` for home rows.
public enum ItemMenuSource: Hashable, Sendable {
    case other
    case continueWatching
    case nextUp
    /// Wholphin's combined Continue Watching and Next Up row.
    case continueWatchingAndNextUp
}

/// What a card's menu knows about the user's history with its item. Cards on item pages know
/// it all; home rows and library grids hold only a `MediaItem`, so whether those items are
/// watched or favourites is unknown (`nil`) until a menu changes it.
public struct ItemMenuState: Hashable, Sendable {
    public var isPlayed: Bool?
    public var isFavorite: Bool?
    /// Whether there's a position to resume from.
    public var isResumable: Bool

    public init(isPlayed: Bool? = nil, isFavorite: Bool? = nil, isResumable: Bool = false) {
        self.isPlayed = isPlayed
        self.isFavorite = isFavorite
        self.isResumable = isResumable
    }
}

public extension MediaItem {
    /// What a card's menu offers for this item, in Wholphin's order (`buildContextMenuItems`,
    /// and its menu for people).
    ///
    /// Where the state is unknown, both ways are offered ("Mark as watched" and "Mark as
    /// unwatched"), since the menu can't ask the server before it opens. Left out until Anemone
    /// has them: shuffle, track and version choice, media information, "play with", music
    /// entries, and delete, which comes with item page extras.
    ///
    /// - Parameter canGoTo: whether the card's page can open other pages.
    func menuEntries(
        state: ItemMenuState,
        source: ItemMenuSource = .other,
        canGoTo: Bool = true,
    ) -> [ItemMenuEntry] {
        if kind == .person {
            return (canGoTo ? [.goTo] : []) + Self.toggles(state.isFavorite, ItemMenuEntry.setFavorite)
        }
        var entries: [ItemMenuEntry] = []
        // Songs have no page of their own.
        if canGoTo, kind != .audio {
            entries.append(.goTo)
        }
        if Self.playableKinds.contains(kind) {
            entries += state.isResumable ? [.resume, .restart] : [.play]
        }
        entries.append(.addToPlaylist)
        let inContinueWatching = source == .continueWatching || source == .continueWatchingAndNextUp
        if inContinueWatching, state.isPlayed != true, state.isResumable {
            entries.append(.removeFromContinueWatching)
        }
        let inNextUp = source == .nextUp || source == .continueWatchingAndNextUp
        if inNextUp, kind == .episode, episode?.seriesID != nil {
            entries.append(.removeFromNextUp)
        }
        entries += Self.toggles(state.isPlayed, ItemMenuEntry.setPlayed)
        entries += Self.toggles(state.isFavorite, ItemMenuEntry.setFavorite)
        if canGoTo, let series = seriesStandIn {
            entries.append(.goToSeries(series))
        }
        return entries
    }

    /// The opposite of what's known, or both ways when nothing is.
    private static func toggles(_ current: Bool?, _ entry: (Bool) -> ItemMenuEntry) -> [ItemMenuEntry] {
        current.map { [entry(!$0)] } ?? [entry(true), entry(false)]
    }

    /// Wholphin's `supportedPlayableTypes` that Anemone plays. Music plays in Phase 5, and Live
    /// TV with the guide.
    private static let playableKinds: Set<Kind> = [.movie, .episode, .video, .musicVideo]
}

public extension ItemDetails {
    /// What a card showing these details knows.
    var menuState: ItemMenuState {
        ItemMenuState(
            isPlayed: userState.isPlayed,
            isFavorite: userState.isFavorite,
            isResumable: userState.resumePosition != nil,
        )
    }
}
