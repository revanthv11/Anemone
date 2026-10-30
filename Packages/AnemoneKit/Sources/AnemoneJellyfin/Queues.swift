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
    /// `videoKinds` as the server names them, to ask it for videos alone.
    static let videoItemTypes: [BaseItemKind] = [.movie, .episode, .video, .musicVideo]

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
    /// places between seasons, which plays first, as in Wholphin, then the regular episodes after
    /// it. A special next up after the last season plays with any specials after it, as in
    /// Wholphin, rather than the series starting over.
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
            // The server starts the list at the episode next up.
            if let first = fromNextUp.first {
                let after = fromNextUp.dropFirst()
                let regular = after.filter { !$0.isSpecial }
                return [first] + (first.isSpecial && regular.isEmpty ? Array(after) : regular)
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
    /// Wholphin's Play takes them, or at random. Up to `queueLimit` videos, as in Wholphin, which
    /// leaves out the rest without a word; this counts them, so the player can say so. The server
    /// is asked for videos alone, as Wholphin asks, so the limit leaves out videos only past it.
    ///
    /// In the collection's own order, the page's order is followed item by item (see
    /// `collectionQueue(following:of:filter:)`): asked for everything in the collection at once,
    /// as Wholphin asks, the server sorts by name instead. `shown` is what the page lists, so it
    /// isn't asked for again; it's asked for when the page hasn't loaded.
    func collectionQueue(
        id: MediaItem.ID,
        shuffled: Bool,
        sort: LibrarySort = LibrarySort(.default),
        filter: LibraryFilter = LibraryFilter(),
        shown: [ItemDetails]? = nil,
    ) async throws -> PlayableItems {
        guard shuffled || sort.field != .default else {
            let page = if let shown {
                shown
            } else {
                try await collectionItems(id: id, sort: sort, filter: filter)
            }
            return try await collectionQueue(following: page, of: id, filter: filter)
        }
        var parameters = collectionParameters(id: id, sort: sort, filter: filter)
        if shuffled {
            parameters.sortBy = [.random]
            parameters.sortOrder = nil
        }
        parameters.includeItemTypes = PlayableItems.videoItemTypes
        parameters.limit = Self.queueLimit
        parameters.enableTotalRecordCount = true
        parameters.fields = Self.queueFields
        parameters.enableUserData = true
        // The videos and the count of everything don't wait for each other.
        let request = Paths.getItems(parameters: parameters)
        async let asked = send(request)
        async let counted = collectionCount(id: id, filter: filter)
        let (found, everything) = try await (asked, counted)
        let videos = found.items.available
        let videoCount = found.totalRecordCount ?? videos.count
        return PlayableItems(
            items: videos,
            skippedCount: max(0, everything - videoCount),
            overLimitCount: max(0, videoCount - (found.items?.count ?? 0)),
        )
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

/// A collection played in its own order.
extension JellyfinSession {
    /// How deep collections inside collections are gone into.
    private static let collectionDepth = 4

    /// A collection's queue in the order its page lists `page`, item by item: a video where it's
    /// listed; a series' or season's episodes where it is, in order whichever way the page is
    /// sorted; and what's in a collection inside it where that collection is, in its own order.
    /// Each item plays once, at its first place. Up to `queueLimit` videos.
    ///
    /// When there are more, or the walk left something out, the server counts what's left out,
    /// as for Shuffle, so both count alike: each song of an album, say, rather than the album.
    /// A collection too deep inside to go into counts as left out too, with what's in it.
    func collectionQueue(
        following page: [ItemDetails],
        of id: MediaItem.ID,
        filter: LibraryFilter,
    ) async throws -> PlayableItems {
        var walk = CollectionWalk(collection: id)
        try await add(page, to: &walk, filter: filter, depth: 0)
        let queued = walk.items.count
        if walk.isFull {
            // Neither count waits for the other.
            async let videos = collectionCount(id: id, filter: filter, kinds: PlayableItems.videoItemTypes)
            async let everything = collectionCount(id: id, filter: filter)
            let (videoCount, allCount) = try await (videos, everything)
            return PlayableItems(
                items: walk.items,
                skippedCount: max(0, allCount - videoCount),
                overLimitCount: max(0, videoCount - queued),
            )
        }
        guard walk.leftOutCount > 0 else {
            return PlayableItems(items: walk.items)
        }
        // Everything there is that isn't queued, since all the videos it could reach are.
        let allCount = try await collectionCount(id: id, filter: filter)
        return PlayableItems(items: walk.items, skippedCount: max(walk.leftOutCount, allCount - queued))
    }

    private func add(
        _ page: [ItemDetails],
        to walk: inout CollectionWalk,
        filter: LibraryFilter,
        depth: Int,
    ) async throws {
        for details in page {
            guard !walk.isFull else { return }
            switch details.item.kind {
            case .series, .season:
                guard walk.enter(details.id) else { continue }
                try await addEpisodes(in: details.id, to: &walk, filter: filter)
            case .collection, .folder:
                // Never round and round, should collections hold each other.
                guard !walk.hasSeen(details.id) else { continue }
                guard depth < Self.collectionDepth else {
                    walk.leaveOut(details.id)
                    continue
                }
                _ = walk.enter(details.id)
                let inside = try await collectionItems(id: details.id, sort: LibrarySort(.default), filter: filter)
                try await add(inside, to: &walk, filter: filter, depth: depth + 1)
            case let kind where PlayableItems.videoKinds.contains(kind):
                walk.add([details])
            default:
                walk.leaveOut(details.id)
            }
        }
    }

    /// A series' or season's episodes, as many as fit, asked for again from where the last
    /// answer ended while there's room: episodes already queued, such as one the page lists on
    /// its own, don't take the place of the ones after them.
    ///
    /// A server that sends nothing it hasn't sent already, such as one that ignores where to
    /// start and sends the first episodes again, isn't asked again. Nor is any server asked more
    /// times than a queue has places: each answer gone on from has an episode not sent before,
    /// which is queued then or already was.
    private func addEpisodes(
        in containerID: MediaItem.ID,
        to walk: inout CollectionWalk,
        filter: LibraryFilter,
    ) async throws {
        var start = 0
        var sent: Set<MediaItem.ID> = []
        for _ in 0 ..< Self.queueLimit {
            guard !walk.isFull else { return }
            let limit = walk.room
            let page = try await episodes(in: containerID, filter: filter, from: start, limit: limit)
            walk.add(page.episodes)
            let isNew = !sent.isSuperset(of: page.sentIDs)
            sent.formUnion(page.sentIDs)
            // Fewer than asked for: those were the last.
            guard page.sentIDs.count == limit, isNew else { return }
            start += limit
        }
    }

    /// A series' or season's episodes in order, the Specials season's first, with the page's
    /// filters, as Wholphin's Play All filters what's inside a collection; and the IDs of all
    /// the server sent, before any are left out.
    private func episodes(
        in containerID: MediaItem.ID,
        filter: LibraryFilter,
        from start: Int,
        limit: Int,
    ) async throws -> (episodes: [ItemDetails], sentIDs: [MediaItem.ID]) {
        var parameters = Paths.GetItemsParameters(userID: userID)
        filter.apply(to: &parameters)
        parameters.parentID = containerID
        parameters.isRecursive = true
        parameters.includeItemTypes = PlayableItems.videoItemTypes
        parameters.filters = [.isNotFolder]
        parameters.excludeLocationTypes = [.virtual]
        parameters.sortBy = [.parentIndexNumber, .indexNumber, .sortName]
        parameters.sortOrder = [.ascending, .ascending, .ascending]
        parameters.startIndex = start > 0 ? start : nil
        parameters.limit = limit
        parameters.fields = Self.queueFields
        parameters.enableUserData = true
        let items = try await send(Paths.getItems(parameters: parameters)).items
        return (items.available, items?.compactMap(\.id) ?? [])
    }

    /// How many items, or items of `kinds`, are in a collection and what's inside it, as the
    /// server counts them without sending them.
    private func collectionCount(
        id: MediaItem.ID,
        filter: LibraryFilter,
        kinds: [BaseItemKind]? = nil,
    ) async throws -> Int {
        var parameters = collectionParameters(id: id, sort: LibrarySort(.default), filter: filter)
        parameters.includeItemTypes = kinds
        parameters.limit = 0
        parameters.enableTotalRecordCount = true
        return try await send(Paths.getItems(parameters: parameters)).totalRecordCount ?? 0
    }

    /// Everything in a collection and in the collections and series inside it: the items, not
    /// the folders holding them, nor episodes the server only knows about.
    private func collectionParameters(
        id: MediaItem.ID,
        sort: LibrarySort,
        filter: LibraryFilter,
    ) -> Paths.GetItemsParameters {
        let collection = Library(id: id, name: "", kind: .collections)
        var parameters = LibraryQuery(library: collection, sort: sort, filter: filter).itemsParameters(userID: userID)
        parameters.includeItemTypes = nil
        parameters.isRecursive = true
        parameters.filters = [.isNotFolder]
        parameters.excludeLocationTypes = [.virtual]
        return parameters
    }
}

private extension BaseItemDto {
    /// On the server, rather than an episode it only knows about.
    var isAvailable: Bool {
        locationType != .virtual
    }
}

extension [BaseItemDto]? {
    /// The items that are on the server, not only listed, as queues take them.
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
