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
    /// Plays a series, season, collection or playlist in a random order.
    case shuffle
    case addToPlaylist
    /// Deletes the item from the server, after asking.
    case delete
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
    /// has them: track and version choice, media information, "play with" and music entries.
    ///
    /// - Parameters:
    ///   - canGoTo: whether the card's page can open other pages.
    ///   - canDelete: whether Delete is offered: the server lets the user delete the item and
    ///     "Show media management options" is on, as Wholphin's `MediaManagementService` decides.
    func menuEntries(
        state: ItemMenuState,
        source: ItemMenuSource = .other,
        canGoTo: Bool = true,
        canDelete: Bool = false,
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
            // What's in a series or collection plays from its own resume positions, so a card
            // whose progress counts its watched episodes still offers Play, not Resume.
            entries += state.isResumable && !playsAsQueue ? [.resume, .restart] : [.play]
        }
        if Self.shufflableKinds.contains(kind) {
            entries.append(.shuffle)
        }
        entries.append(.addToPlaylist)
        if canDelete {
            entries.append(.delete)
        }
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

    /// Wholphin's `supportedPlayableTypes` that Anemone plays from a menu: videos, and the
    /// series, seasons, collections and playlists whose Play queues them up (3b). Music plays
    /// in Phase 5, and Live TV with the guide.
    private static let playableKinds: Set<Kind> = [
        .movie, .episode, .video, .musicVideo, .series, .season, .collection, .playlist,
    ]
    /// Wholphin's `supportedShufflableTypes`.
    private static let shufflableKinds: Set<Kind> = [.series, .season, .collection, .playlist]

    /// Whether Play on this item queues up what's in it, rather than playing the item itself.
    var playsAsQueue: Bool {
        Self.shufflableKinds.contains(kind)
    }
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
