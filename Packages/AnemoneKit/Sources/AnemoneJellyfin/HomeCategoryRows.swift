import AnemoneCore
import Foundation
import Get
import JellyfinAPI

/// Genre and studio rows, and rows from other plugins' endpoints, ported from Wholphin's
/// `HomeDataService` and `getGenreImageMap`.
extension JellyfinSession {
    /// A library's genres or studios, each opening a grid of its items in that library.
    func categoryRow(_ kind: HomeRowConfig.Kind, context: HomeRowContext) async throws -> HomeRowData {
        guard let parentID = HomeRowConfig(kind).parentID else { return HomeRowData(cards: []) }
        let library = context.library(parentID) ?? Library(id: parentID, name: "", kind: .mixed)
        if case .studios = kind {
            return try await HomeRowData(cards: studioCards(in: library, limit: context.limit))
        }
        return try await HomeRowData(cards: genreCards(in: library, context: context))
    }

    private func genreCards(in library: Library, context: HomeRowContext) async throws -> [HomeCard] {
        let parameters = Paths.GetGenresParameters(limit: context.limit, parentID: library.id, userID: userID)
        let genres = try await (send(Paths.getGenres(parameters: parameters)).items ?? []).compactMap(MediaItem.init)
        let images = await genreImages(genres.map(\.id), in: library.id, context: context)
        return genres.map { genre in
            var filter = LibraryFilter()
            filter.genres = [genre.id]
            return HomeCard(
                item: genre,
                image: images[genre.id],
                destination: .items(HomeItemsLink(
                    title: genre.name,
                    query: LibraryQuery(library: library, filter: filter),
                )),
            )
        }
    }

    /// A backdrop for each genre, from one of its items picked at random. Kept while the page
    /// refreshes, as Wholphin keeps them, so the art doesn't change every time Home shows; a genre
    /// new since, or whose lookup failed, is looked up then.
    private func genreImages(
        _ genreIDs: [String],
        in parentID: String,
        context: HomeRowContext,
    ) async -> [String: ItemImage] {
        let cache = context.options.cache
        var art = context.options.isRefresh ? await cache.genreArt(for: parentID) ?? GenreArt() : GenreArt()
        let missing = genreIDs.filter { !art.lookedUp.contains($0) }
        guard !missing.isEmpty else { return art.images }
        let found = await boundedMap(missing.count, width: 4) { index in
            await (missing[index], attempt { try await genreImage(missing[index], in: parentID) })
        }
        for (id, result) in found {
            guard case let .success(image) = result else { continue }
            art.lookedUp.insert(id)
            art.images[id] = image
        }
        await cache.setGenreArt(art, for: parentID)
        return art.images
    }

    private func genreImage(_ genreID: String, in parentID: String) async throws -> ItemImage? {
        var parameters = Paths.GetItemsParameters(userID: userID)
        parameters.parentID = parentID
        parameters.isRecursive = true
        parameters.limit = 1
        parameters.sortBy = [.random]
        parameters.fields = [.genres]
        parameters.imageTypes = [.backdrop]
        parameters.imageTypeLimit = 1
        parameters.genreIDs = [genreID]
        parameters.enableTotalRecordCount = false
        return try await items(parameters).first?.backdropImage
    }

    /// Studios of a library's series, as Wholphin asks for them, each with its own thumb.
    private func studioCards(in library: Library, limit: Int) async throws -> [HomeCard] {
        let parameters = Paths.GetStudiosParameters(
            limit: limit,
            parentID: library.id,
            includeItemTypes: [.series],
            userID: userID,
        )
        let studios = try await (send(Paths.getStudios(parameters: parameters)).items ?? []).compactMap(MediaItem.init)
        return studios.map { studio in
            var filter = LibraryFilter()
            filter.studios = [studio.id]
            return HomeCard(
                item: studio,
                image: studio.artwork.thumbTag.map { ItemImage(itemID: studio.id, kind: .thumb, tag: $0) },
                destination: .items(HomeItemsLink(
                    title: studio.name,
                    query: LibraryQuery(library: library, filter: filter),
                )),
            )
        }
    }

    /// Items from another plugin's endpoint, such as Home Screen Sections, as Wholphin's
    /// `fetchCustomEndpointItems`: a path on this server, given the user's ID and the row's query
    /// and headers, answering with an item query result.
    ///
    /// - Throws: `HomeRowError.endpointNotOnServer` for a full URL, which would send the token
    ///   to another server.
    func customEndpointItems(_ endpoint: HomeCustomEndpoint) async throws -> [MediaItem] {
        guard let components = URLComponents(string: endpoint.endpoint), components.scheme == nil,
              components.host == nil, !components.path.isEmpty
        else { throw HomeRowError.endpointNotOnServer }
        var query: [(String, String?)] = [("userId", userID)]
        for entry in endpoint.query ?? [] {
            query.removeAll { $0.0 == entry.key }
            query.append((entry.key, entry.value))
        }
        let request = Request<BaseItemDtoQueryResult>(
            path: components.path,
            query: (components.queryItems ?? []).map { ($0.name, $0.value) } + query,
            headers: endpoint.headers.map { Dictionary($0.map { ($0.key, $0.value) }) { _, last in last } },
        )
        return try await (send(request).items ?? []).compactMap(MediaItem.init)
    }
}

public enum HomeRowError: Error, Equatable {
    /// A custom endpoint must be a path on the user's server.
    case endpointNotOnServer
    /// Suggestions are only worked out for movie and TV libraries.
    case noSuggestions
}
