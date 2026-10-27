import Foundation
import Get
import JellyfinAPI

/// Music requests, ported from Wholphin's music view models and `MusicService`.
public extension JellyfinSession {
    /// One page of a music library tab, from `startIndex`.
    func musicPage(
        _ list: MusicList,
        sort: MusicSort,
        startIndex: Int,
        limit: Int,
        includeTotalCount: Bool = false,
    ) async throws -> MusicPage {
        var parameters = Paths.GetItemsParameters(userID: userID)
        parameters.startIndex = startIndex
        parameters.limit = limit
        parameters.enableTotalRecordCount = includeTotalCount
        parameters.isRecursive = true
        parameters.fields = Self.musicFields
        parameters.enableUserData = true
        parameters.imageTypeLimit = 1
        (parameters.sortBy, parameters.sortOrder) = Self.sortParameters(sort)
        let result: BaseItemDtoQueryResult
        switch list {
        case let .albums(library):
            parameters.parentID = library
            parameters.includeItemTypes = [.musicAlbum]
            result = try await send(Paths.getItems(parameters: parameters))
        case let .genre(genreID, library):
            parameters.parentID = library
            parameters.genreIDs = [genreID]
            parameters.includeItemTypes = [.musicAlbum]
            result = try await send(Paths.getItems(parameters: parameters))
        case let .songs(library):
            parameters.parentID = library
            parameters.includeItemTypes = [.audio]
            result = try await send(Paths.getItems(parameters: parameters))
        case let .artists(library):
            let artists = Paths.GetArtistsParameters(
                startIndex: startIndex,
                limit: limit,
                parentID: library,
                fields: Self.musicFields,
                enableUserData: true,
                imageTypeLimit: 1,
                enableImageTypes: [.primary, .thumb],
                userID: userID,
                sortBy: parameters.sortBy,
                sortOrder: parameters.sortOrder,
                enableTotalRecordCount: includeTotalCount,
            )
            // `GET /Artists`, as `Paths.getArtists` sends it. The SDK marks that deprecated, but
            // it's still how Wholphin lists a library's artists; built here, as Search does, so
            // the build stays free of the warning.
            result = try await send(Request(path: "/Artists", method: "GET", query: artists.asQuery, id: "GetArtists"))
        }
        let items = result.items.musicItems
        return MusicPage(items: items, totalCount: includeTotalCount ? result.totalRecordCount ?? items.count : nil)
    }

    /// The albums for a row on the Recommended tab, as Wholphin's `RecommendedMusic` asks for them.
    func recommendedAlbums(
        _ row: MusicRecommendation,
        in libraryID: Library.ID,
        limit: Int,
        now: Date = .now,
    ) async throws -> [MusicItem] {
        var parameters = albumParameters(limit: limit)
        parameters.parentID = libraryID
        switch row {
        case .recentlyReleased:
            parameters.sortBy = [.premiereDate, .sortName]
            parameters.sortOrder = [.descending, .ascending]
            parameters.maxPremiereDate = now
        case .recentlyAdded:
            parameters.sortBy = [.dateCreated]
            parameters.sortOrder = [.descending]
        case .topRated:
            parameters.sortBy = [.communityRating]
            parameters.sortOrder = [.descending]
        }
        return try await send(Paths.getItems(parameters: parameters)).items.musicItems
    }

    /// The Recommended tab's Suggestions row: Wholphin's mix (`SuggestionService`) for albums.
    func musicSuggestions(in libraryID: Library.ID, limit: Int) async throws -> [MusicItem] {
        let ids = try await pickSuggestions(in: libraryID, kind: .musicAlbum, count: limit)
        guard !ids.isEmpty else { return [] }
        var parameters = albumParameters(limit: nil)
        parameters.ids = ids
        // The server returns them in its own order; keep the picks' order.
        let albums = try await send(Paths.getItems(parameters: parameters)).items.musicItems
        return ids.compactMap { id in albums.first { $0.id == id } }
    }

    /// An album, artist or song for its page, with its artists.
    func musicItem(id: MediaItem.ID) async throws -> MusicItem {
        guard let item = try await MusicItem(send(Paths.getItem(itemID: id, userID: userID))) else {
            throw SessionError.unexpectedResponse
        }
        return item
    }

    /// An album's songs in order: by disc, then track, then name.
    func songs(onAlbum albumID: MediaItem.ID) async throws -> [MusicItem] {
        try await songs(from: .album(albumID), startIndex: 0, limit: nil).items
    }

    /// Songs to queue from `source`, a page at a time, in Wholphin's order for each.
    ///
    /// - Parameter shuffled: for a large source, asks the server for a random order, so a
    ///   shuffled queue draws from all of it.
    func songs(
        from source: MusicSource,
        shuffled: Bool = false,
        startIndex: Int,
        limit: Int?,
    ) async throws -> MusicPage {
        var parameters = Paths.GetItemsParameters(userID: userID)
        parameters.startIndex = startIndex
        parameters.limit = limit
        parameters.enableTotalRecordCount = startIndex == 0
        parameters.includeItemTypes = [.audio]
        parameters.fields = Self.songFields
        parameters.enableUserData = true
        parameters.imageTypeLimit = 1
        let trackOrder: [ItemSortBy] = [.parentIndexNumber, .indexNumber, .sortName]
        switch source {
        case let .album(id):
            parameters.parentID = id
            parameters.sortBy = trackOrder
        case let .artist(id):
            parameters.artistIDs = [id]
            parameters.isRecursive = true
            parameters.sortBy = trackOrder
        case let .playlist(id):
            parameters.parentID = id
            parameters.isRecursive = true
            parameters.sortBy = [.default]
        case let .library(id):
            parameters.parentID = id
            parameters.isRecursive = true
            parameters.sortBy = [.albumArtist, .album] + trackOrder
        case let .songs(library, sort):
            // The same order as the tab's `musicPage`.
            parameters.parentID = library
            parameters.isRecursive = true
            (parameters.sortBy, parameters.sortOrder) = Self.sortParameters(sort)
        case let .genre(genreID, library):
            parameters.parentID = library
            parameters.genreIDs = [genreID]
            parameters.isRecursive = true
            parameters.sortBy = [.albumArtist, .album] + trackOrder
        }
        if shuffled, source.isLarge {
            parameters.sortBy = [.random]
            parameters.sortOrder = nil
        }
        let result = try await send(Paths.getItems(parameters: parameters))
        let items = result.items.musicItems
        return MusicPage(items: items, totalCount: startIndex == 0 ? result.totalRecordCount ?? items.count : nil)
    }

    /// Wholphin's artist page rows: albums by the artist, newest first.
    func albums(byArtist artistID: MediaItem.ID) async throws -> [MusicItem] {
        var parameters = albumParameters(limit: nil)
        parameters.albumArtistIDs = [artistID]
        parameters.sortBy = [.premiereDate, .sortName]
        parameters.sortOrder = [.descending, .ascending]
        return try await send(Paths.getItems(parameters: parameters)).items.musicItems
    }

    /// "Appears On": albums the artist contributes to without being their artist.
    func albums(featuringArtist artistID: MediaItem.ID) async throws -> [MusicItem] {
        var parameters = albumParameters(limit: nil)
        parameters.contributingArtistIDs = [artistID]
        parameters.sortBy = [.premiereDate, .sortName]
        parameters.sortOrder = [.descending, .ascending]
        return try await send(Paths.getItems(parameters: parameters)).items.musicItems
    }

    /// "Popular Songs": the artist's ten best-rated songs that have a rating, as Wholphin asks.
    func popularSongs(byArtist artistID: MediaItem.ID) async throws -> [MusicItem] {
        var parameters = Paths.GetItemsParameters(userID: userID)
        parameters.artistIDs = [artistID]
        parameters.isRecursive = true
        parameters.includeItemTypes = [.audio]
        parameters.minCommunityRating = 1
        parameters.sortBy = [.communityRating]
        parameters.sortOrder = [.descending]
        parameters.limit = 10
        parameters.fields = Self.songFields
        parameters.enableUserData = true
        return try await send(Paths.getItems(parameters: parameters)).items.musicItems
    }

    /// "More Like This" for an album or artist, leaving out the artists' own work as Wholphin
    /// does. Up to 25.
    func similarMusic(to itemID: MediaItem.ID, excludingArtists artistIDs: [String]) async throws -> [MusicItem] {
        let parameters = Paths.GetSimilarItemsParameters(
            excludeArtistIDs: artistIDs.isEmpty ? nil : artistIDs,
            userID: userID,
            limit: 25,
            fields: Self.musicFields,
        )
        return try await send(Paths.getSimilarItems(itemID: itemID, parameters: parameters)).items.musicItems
    }

    /// Wholphin's instant mix: up to 200 songs like the item, chosen by the server.
    func instantMix(from itemID: MediaItem.ID) async throws -> [MusicItem] {
        let parameters = Paths.GetInstantMixFromItemParameters(
            userID: userID,
            limit: 200,
            fields: Self.songFields,
            enableUserData: true,
        )
        return try await send(Paths.getInstantMixFromItem(itemID: itemID, parameters: parameters)).items.musicItems
    }

    /// The library's album genres, each with the cover of a random album in it, as Wholphin's
    /// genre grid shows them.
    func musicGenres(in libraryID: Library.ID) async throws -> [MusicGenre] {
        let parameters = Paths.GetGenresParameters(
            parentID: libraryID,
            includeItemTypes: [.musicAlbum],
            userID: userID,
            sortBy: [.sortName],
        )
        let genres = try await (send(Paths.getGenres(parameters: parameters)).items ?? []).compactMap { dto in
            dto.id.map { MusicGenre(id: $0, name: dto.name ?? "") }
        }
        let covers = await boundedMap(genres.count, width: 4) { [self] index in
            try? await genreCover(genres[index].id, in: libraryID)
        }
        return zip(genres, covers).map { genre, cover in
            var genre = genre
            genre.image = cover
            return genre
        }
    }

    private func genreCover(_ genreID: String, in libraryID: Library.ID) async throws -> ItemImage? {
        var parameters = albumParameters(limit: 1)
        parameters.parentID = libraryID
        parameters.genreIDs = [genreID]
        parameters.sortBy = [.random]
        parameters.imageTypes = [.primary]
        parameters.enableTotalRecordCount = false
        return try await send(Paths.getItems(parameters: parameters)).items.musicItems.first?.coverImage
    }

    private func albumParameters(limit: Int?) -> Paths.GetItemsParameters {
        var parameters = Paths.GetItemsParameters(userID: userID)
        parameters.isRecursive = true
        parameters.includeItemTypes = [.musicAlbum]
        parameters.fields = Self.musicFields
        parameters.enableUserData = true
        parameters.imageTypeLimit = 1
        parameters.limit = limit
        parameters.enableTotalRecordCount = false
        return parameters
    }

    /// The chosen field, then name to break ties.
    private static func sortParameters(_ sort: MusicSort) -> ([ItemSortBy], [JellyfinAPI.SortOrder]) {
        let field = ItemSortBy(rawValue: sort.field.rawValue) ?? .sortName
        let order: JellyfinAPI.SortOrder = sort.direction == .ascending ? .ascending : .descending
        guard sort.field != .name else { return ([field], [order]) }
        return ([field, .sortName], [order, .ascending])
    }

    /// Cards need the sort name for the alphabet, and pages the overview and genres.
    private static let musicFields: [ItemFields] = [.sortName, .overview, .genres, .childCount]
    /// Songs also need their streams, for the AC3 choice.
    private static let songFields: [ItemFields] = [.sortName, .mediaStreams]
}
