import Foundation
import Get
import JellyfinAPI

/// One row of a collection page: the collection's items of one type.
public struct CollectionSection: Hashable, Identifiable, Sendable {
    public let kind: MediaItem.Kind
    public let items: [ItemDetails]

    public init(kind: MediaItem.Kind, items: [ItemDetails]) {
        self.kind = kind
        self.items = items
    }

    public var id: MediaItem.Kind {
        kind
    }

    /// The types Wholphin gives their own rows, in its order. Music artists come with music in
    /// Phase 5.
    public static let kinds: [MediaItem.Kind] = [
        .movie,
        .series,
        .episode,
        .video,
        .collection,
        .musicAlbum,
        .musicVideo,
    ]

    /// Splits a collection's items into rows by type, keeping the server's order within each row.
    /// Types without a row are left out, as are empty rows.
    public static func sections(_ items: [ItemDetails]) -> [Self] {
        let byKind = Dictionary(grouping: items, by: \.item.kind)
        return kinds.compactMap { kind in
            byKind[kind].map { Self(kind: kind, items: $0) }
        }
    }
}

/// The rows of a person's page.
public enum FilmographyRow: CaseIterable, Hashable, Sendable {
    case movies
    case series
    case episodes
}

public extension ItemDetails.CreditCounts {
    /// Whether a row is worth asking for: skipped only when the server says there's nothing in it.
    func mayHave(_ row: FilmographyRow) -> Bool {
        let count = switch row {
        case .movies: movies
        case .series: series
        case .episodes: episodes
        }
        return count.map { $0 > 0 } ?? true
    }
}

/// Queries and actions for item pages, ported from Wholphin's detail view models.
public extension JellyfinSession {
    /// Everything about one item. `/Items/{id}` sends every field, people included.
    func itemDetails(id: MediaItem.ID) async throws -> ItemDetails {
        guard let details = try await ItemDetails(send(Paths.getItem(itemID: id, userID: userID))) else {
            throw SessionError.unexpectedResponse
        }
        return details
    }

    /// A series' seasons in order.
    func seasons(ofSeries seriesID: String) async throws -> [ItemDetails] {
        let parameters = Paths.GetItemsParameters(
            userID: userID,
            isRecursive: false,
            sortOrder: [.ascending],
            parentID: seriesID,
            fields: Self.rowFields,
            includeItemTypes: [.season],
            sortBy: [.indexNumber],
            enableUserData: true,
        )
        return try await send(Paths.getItems(parameters: parameters)).items.details
    }

    /// A season's episodes in order. They come with their cast and crew, so the season page can
    /// show the focused episode's people without asking for each one.
    func episodes(ofSeries seriesID: String, season seasonID: String) async throws -> [ItemDetails] {
        let parameters = Paths.GetEpisodesParameters(
            userID: userID,
            fields: Self.rowFields + [.people],
            seasonID: seasonID,
            enableUserData: true,
            sortBy: .indexNumber,
        )
        return try await send(Paths.getEpisodes(seriesID: seriesID, parameters: parameters)).items.details
    }

    /// "More like this": Wholphin shows up to 25.
    func similarItems(to itemID: MediaItem.ID, limit: Int = 25) async throws -> [ItemDetails] {
        let parameters = Paths.GetSimilarItemsParameters(userID: userID, limit: limit, fields: Self.rowFields)
        return try await send(Paths.getSimilarItems(itemID: itemID, parameters: parameters)).items.details
    }

    /// A playlist's items in the playlist's order.
    func playlistItems(id: MediaItem.ID) async throws -> [ItemDetails] {
        let parameters = Paths.GetPlaylistItemsParameters(userID: userID, fields: Self.rowFields, enableUserData: true)
        return try await send(Paths.getPlaylistItems(playlistID: id, parameters: parameters)).items.details
    }

    /// One row of a person's page, newest first, with the same sort as Wholphin.
    func filmography(ofPerson personID: MediaItem.ID, row: FilmographyRow) async throws -> [ItemDetails] {
        let kind: BaseItemKind = switch row {
        case .movies: .movie
        case .series: .series
        case .episodes: .episode
        }
        let parameters = Paths.GetItemsParameters(
            userID: userID,
            isRecursive: true,
            sortOrder: [.descending, .descending, .ascending],
            fields: Self.rowFields,
            includeItemTypes: [kind],
            sortBy: [.premiereDate, .productionYear, .sortName],
            enableUserData: true,
            personIDs: [personID],
        )
        return try await send(Paths.getItems(parameters: parameters)).items.details
    }

    /// Whether the user may reorder a playlist, which Wholphin checks before showing its move
    /// buttons. The server says "not found" when the user has no say over the playlist; any
    /// failure other than a sign-out counts as no.
    func canEditPlaylist(id: MediaItem.ID) async throws -> Bool {
        do {
            return try await send(Paths.getPlaylistUser(playlistID: id, userID: userID)).canEdit ?? false
        } catch SessionError.signedOut {
            throw SessionError.signedOut
        } catch {
            return false
        }
    }

    /// Moves a playlist entry to `index`, counting from 0.
    func movePlaylistItem(_ itemID: MediaItem.ID, inPlaylist playlistID: MediaItem.ID, to index: Int) async throws {
        try await send(Paths.moveItem(playlistID: playlistID, itemID: itemID, newIndex: index))
    }

    /// Marks an item watched or unwatched. For a series or season, the server marks every
    /// episode.
    @discardableResult
    func setPlayed(_ isPlayed: Bool, itemID: MediaItem.ID) async throws -> ItemDetails.UserState {
        let request = isPlayed
            ? Paths.markPlayedItem(itemID: itemID, userID: userID)
            : Paths.markUnplayedItem(itemID: itemID, userID: userID)
        return try await ItemDetails.UserState(send(request))
    }

    /// Adds an item, or a person, to the user's favourites, or removes it.
    @discardableResult
    func setFavorite(_ isFavorite: Bool, itemID: MediaItem.ID) async throws -> ItemDetails.UserState {
        let request = isFavorite
            ? Paths.markFavoriteItem(itemID: itemID, userID: userID)
            : Paths.unmarkFavoriteItem(itemID: itemID, userID: userID)
        return try await ItemDetails.UserState(send(request))
    }

    /// Fields for rows on item pages: the focused item's overview, card shapes, and episode or
    /// item counts.
    private static let rowFields: [ItemFields] = [.overview, .primaryImageAspectRatio, .childCount]
}

extension JellyfinSession {
    /// For requests the server answers without a body.
    func send(_ request: Request<Void>) async throws {
        do {
            try await client.send(request)
        } catch APIError.unacceptableStatusCode(401) {
            throw SessionError.signedOut
        }
    }
}

public extension [ItemDetails] {
    /// Where a season or episode is in this list: matched by id, then by number, like Wholphin's
    /// `findIndexByNumberOrId`. The first item when neither matches.
    func index(ofID id: String?, number: Int?) -> Int {
        if let id, let index = firstIndex(where: { $0.id == id }) {
            return index
        }
        if let number, let index = firstIndex(where: { $0.indexNumber == number }) {
            return index
        }
        return 0
    }
}

private extension [BaseItemDto]? {
    var details: [ItemDetails] {
        (self ?? []).compactMap(ItemDetails.init)
    }
}
