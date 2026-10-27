import Foundation
import JellyfinAPI

/// What a collection or playlist plays: its videos in order, and how many other items, such as
/// music or photos, were left out because the video player can't play them.
public struct PlayableItems: Hashable, Sendable {
    public var items: [ItemDetails]
    public var skippedCount: Int
    /// How many more items there were than a queue holds (`JellyfinSession.queueLimit`), left out
    /// at the end.
    public var overLimitCount: Int

    public init(items: [ItemDetails], skippedCount: Int = 0, overLimitCount: Int = 0) {
        self.items = items
        self.skippedCount = skippedCount
        self.overLimitCount = overLimitCount
    }

    /// The kinds the video player plays.
    public static let videoKinds: Set<MediaItem.Kind> = [.movie, .episode, .video, .musicVideo]

    /// - Parameter total: how many items the server has for the query, when it asked for fewer.
    init(_ dtos: [BaseItemDto]?, total: Int? = nil) {
        let found = dtos ?? []
        let items = found.filter(\.isAvailable).compactMap(ItemDetails.init)
        let videos = items.filter { Self.videoKinds.contains($0.item.kind) }
        self.init(
            items: videos,
            skippedCount: items.count - videos.count,
            overLimitCount: max(0, (total ?? found.count) - found.count),
        )
    }
}

/// What Play and Shuffle queue up, ported from Wholphin's `PlaylistCreator`: a series from the
/// episode next up, a season, a collection or a playlist, in order or shuffled. Episodes that
/// are only listed, not on the server, are left out, as in Wholphin.
public extension JellyfinSession {
    /// Wholphin's `Playlist.MAX_SIZE`: queues ask for up to this many items.
    static let queueLimit = 100

    /// Series Play, like Wholphin's: the episode next up (the one to resume, or the one after the
    /// last watched), or the first episode when there's none, then the episodes after it in
    /// order across seasons, without the specials. Jellyfin's next up can be a special the server
    /// places between seasons; Play starts at the regular episode after it instead. A special
    /// next up after the last season plays, with any specials after it, as in Wholphin, rather
    /// than the series starting over.
    func seriesQueue(seriesID: MediaItem.ID) async throws -> [ItemDetails] {
        let parameters = Paths.GetNextUpParameters(
            userID: userID,
            limit: 1,
            fields: Self.queueFields,
            seriesID: seriesID,
            enableUserData: true,
        )
        if let nextUp = try await send(Paths.getNextUp(parameters: parameters)).items?.first?.id {
            let fromNextUp = try await orderedEpisodes(ofSeries: seriesID, from: nextUp)
            let regular = fromNextUp.filter { !$0.isSpecial }
            if !regular.isEmpty {
                return regular
            }
            if !fromNextUp.isEmpty {
                return fromNextUp
            }
        }
        return try await episodes(ofSeries: seriesID, from: nil)
    }

    /// A series' episodes from `episodeID` on, in order across seasons, for playing through: the
    /// specials after it when it's a special, otherwise the regular episodes. From the first
    /// regular episode when `episodeID` is `nil`, or the first special for a series of specials.
    func episodes(ofSeries seriesID: MediaItem.ID, from episodeID: MediaItem.ID?) async throws -> [ItemDetails] {
        let episodes = try await orderedEpisodes(ofSeries: seriesID, from: episodeID)
        // The server starts the list at `episodeID`, wherever it puts the specials.
        let playsSpecials = episodeID != nil && episodes.first?.isSpecial == true
        let played = episodes.filter { $0.isSpecial == playsSpecials }
        return played.isEmpty && episodeID == nil ? episodes : played
    }

    /// Season Play: the season's episodes in order.
    func seasonQueue(seriesID: MediaItem.ID, seasonID: MediaItem.ID) async throws -> [ItemDetails] {
        let parameters = Paths.GetEpisodesParameters(
            userID: userID,
            fields: Self.queueFields,
            seasonID: seasonID,
            limit: Self.queueLimit,
            enableUserData: true,
        )
        return try await send(Paths.getEpisodes(seriesID: seriesID, parameters: parameters)).items.available
    }

    /// Shuffle for a series, or one of its seasons: random episodes, specials included, as in
    /// Wholphin. The server picks them, so a long series shuffles all its episodes.
    func shuffledEpisodes(ofSeries seriesID: MediaItem.ID, season seasonID: MediaItem.ID? = nil) async throws
        -> [ItemDetails]
    {
        let parameters = Paths.GetEpisodesParameters(
            userID: userID,
            fields: Self.queueFields,
            seasonID: seasonID,
            limit: Self.queueLimit,
            enableUserData: true,
            sortBy: .random,
        )
        return try await send(Paths.getEpisodes(seriesID: seriesID, parameters: parameters)).items.available
    }

    /// Play or Shuffle for a collection: everything in it that plays, with the episodes of any
    /// series in it, like Wholphin. In the order and with the filters its page shows, as
    /// Wholphin's Play takes them, or at random. Up to `queueLimit` items, as in Wholphin, which
    /// leaves out the rest without a word; this counts them, so the player can say so.
    ///
    /// In the collection's own order, the page's order is followed item by item: asked for
    /// everything in the collection at once, as Wholphin asks, the server sorts by name instead.
    func collectionQueue(
        id: MediaItem.ID,
        shuffled: Bool,
        sort: LibrarySort = LibrarySort(.default),
        filter: LibraryFilter = LibraryFilter(),
    ) async throws -> PlayableItems {
        let collection = Library(id: id, name: "", kind: .collections)
        var parameters = LibraryQuery(library: collection, sort: sort, filter: filter).itemsParameters(userID: userID)
        let followsPage = !shuffled && sort.field == .default
        if shuffled {
            parameters.sortBy = [.random]
            parameters.sortOrder = nil
        } else if followsPage {
            // Keeps each series' episodes in order.
            parameters.sortBy = [.default]
            parameters.sortOrder = [sort.direction == .ascending ? .ascending : .descending]
        }
        parameters.includeItemTypes = nil
        parameters.isRecursive = true
        parameters.filters = [.isNotFolder]
        parameters.excludeLocationTypes = [.virtual]
        // All of them when they're put in the page's order, which picks the first 100.
        parameters.limit = followsPage ? nil : Self.queueLimit
        parameters.enableTotalRecordCount = true
        parameters.fields = Self.queueFields
        parameters.enableUserData = true
        let found = try await send(Paths.getItems(parameters: parameters))
        guard followsPage, let items = found.items else {
            return PlayableItems(found.items, total: found.totalRecordCount)
        }
        let shown = try await collectionItems(id: id, sort: sort, filter: filter).map(\.id)
        let ordered = Self.ordered(items, like: shown)
        return PlayableItems(Array(ordered.prefix(Self.queueLimit)), total: ordered.count)
    }

    /// Play for a playlist: its entries in the playlist's order, from `/Playlists/{id}/Items`. All
    /// of them, so Shuffle can pick from every one.
    func playlistQueue(id: MediaItem.ID) async throws -> PlayableItems {
        let parameters = Paths.GetPlaylistItemsParameters(
            userID: userID,
            fields: Self.queueFields,
            enableUserData: true,
        )
        return try await PlayableItems(send(Paths.getPlaylistItems(playlistID: id, parameters: parameters)).items)
    }

    /// The player shows the overview in its info panel.
    private static let queueFields: [ItemFields] = [.overview]

    /// `items` in the order of `shown`, a collection's items as its page lists them: each where
    /// it, or the series, season or folder it's in, is listed; anything else after them. Ties
    /// keep the server's order.
    private static func ordered(_ items: [BaseItemDto], like shown: [MediaItem.ID]) -> [BaseItemDto] {
        let places = Dictionary(shown.enumerated().map { ($1, $0) }) { first, _ in first }
        func place(of item: BaseItemDto) -> Int {
            [item.id, item.seriesID, item.seasonID, item.parentID]
                .lazy
                .compactMap { $0.flatMap { places[$0] } }
                .first ?? places.count
        }
        return items.enumerated()
            .sorted { (place(of: $0.element), $0.offset) < (place(of: $1.element), $1.offset) }
            .map(\.element)
    }

    /// The series' episodes from `episodeID` on, specials included where the server puts them.
    private func orderedEpisodes(ofSeries seriesID: MediaItem.ID, from episodeID: MediaItem.ID?) async throws
        -> [ItemDetails]
    {
        let parameters = Paths.GetEpisodesParameters(
            userID: userID,
            fields: Self.queueFields,
            startItemID: episodeID,
            limit: Self.queueLimit,
            enableUserData: true,
        )
        return try await send(Paths.getEpisodes(seriesID: seriesID, parameters: parameters)).items.available
    }
}

private extension BaseItemDto {
    /// On the server, rather than an episode it only knows about.
    var isAvailable: Bool {
        locationType != .virtual
    }
}

private extension [BaseItemDto]? {
    var available: [ItemDetails] {
        (self ?? []).filter(\.isAvailable).compactMap(ItemDetails.init)
    }
}

private extension ItemDetails {
    /// In a series' Specials season.
    var isSpecial: Bool {
        item.kind == .episode && item.episode?.seasonNumber == 0
    }
}
