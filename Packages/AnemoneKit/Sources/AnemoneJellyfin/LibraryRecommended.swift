import Foundation
import JellyfinAPI

/// One row of a library's Recommended tab.
public struct RecommendedRow: Hashable, Identifiable, Sendable {
    /// Wholphin's rows, from `RecommendedMovie` and `RecommendedTvShow`, then its suggestions.
    public enum Kind: String, CaseIterable, Hashable, Sendable {
        case continueWatching
        case nextUp
        case recentlyReleased
        case recentlyAdded
        case topUnwatched
        case suggestions
    }

    public let kind: Kind
    public let items: [MediaItem]

    public init(kind: Kind, items: [MediaItem]) {
        self.kind = kind
        self.items = items
    }

    public var id: Kind {
        kind
    }
}

/// What a library's Recommended tab shows.
public struct RecommendedContent: Hashable, Sendable {
    /// Rows that loaded and have something in them, in order.
    public let rows: [RecommendedRow]
    /// Rows that couldn't be loaded.
    public let failedRows: [RecommendedRow.Kind]

    public init(rows: [RecommendedRow], failedRows: [RecommendedRow.Kind]) {
        self.rows = rows
        self.failedRows = failedRows
    }
}

public extension Library {
    /// The rows of the library's Recommended tab, in Wholphin's order. Only movie and TV
    /// libraries have the tab.
    var recommendedRows: [RecommendedRow.Kind] {
        switch kind {
        case .movies: [.continueWatching, .recentlyReleased, .recentlyAdded, .topUnwatched, .suggestions]
        case .shows: [.continueWatching, .nextUp, .recentlyReleased, .recentlyAdded, .topUnwatched, .suggestions]
        default: []
        }
    }

    /// What Wholphin's suggestions offer from this library: movies, or series.
    internal var suggestionKind: BaseItemKind? {
        switch kind {
        case .movies: .movie
        case .shows: .series
        default: nil
        }
    }
}

public extension JellyfinSession {
    /// A library's Recommended tab. Rows load in parallel; one failing doesn't stop the others.
    ///
    /// - Parameter limit: Wholphin's "max items per row".
    /// - Throws: `SessionError.signedOut` from any row.
    func recommended(
        in library: Library,
        itemsPerRow limit: Int = HomeRow.defaultLimit,
        now: Date = .now,
    ) async throws -> RecommendedContent {
        let kinds = library.recommendedRows
        let results = await withTaskGroup(of: (Int, Result<[MediaItem], any Error>).self) { group in
            for (index, kind) in kinds.enumerated() {
                group.addTask {
                    do {
                        return try await (index, .success(recommendedItems(kind, in: library, limit: limit, now: now)))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            var results = [Result<[MediaItem], any Error>](repeating: .success([]), count: kinds.count)
            for await (index, result) in group {
                results[index] = result
            }
            return results
        }
        var rows: [RecommendedRow] = []
        var failedRows: [RecommendedRow.Kind] = []
        for (kind, result) in zip(kinds, results) {
            switch result {
            case let .success(items) where !items.isEmpty:
                rows.append(RecommendedRow(kind: kind, items: items))
            case .success:
                break
            case let .failure(error):
                if error as? SessionError == .signedOut {
                    throw SessionError.signedOut
                }
                failedRows.append(kind)
            }
        }
        return RecommendedContent(rows: rows, failedRows: failedRows)
    }

    /// One row of a library's Recommended tab, asked for as Wholphin asks. Empty for a row the
    /// library doesn't have, such as Next Up for movies.
    ///
    /// - Parameter now: the latest release date Recently Released shows.
    func recommendedItems(
        _ row: RecommendedRow.Kind,
        in library: Library,
        limit: Int = HomeRow.defaultLimit,
        now: Date = .now,
    ) async throws -> [MediaItem] {
        guard let kind = library.suggestionKind else { return [] }
        let isTV = kind == .series
        switch row {
        case .continueWatching:
            return try await resumeItems(in: library, type: isTV ? .episode : .movie, limit: limit)
        case .nextUp:
            return isTV ? try await nextUpItems(in: library, limit: limit) : []
        case .recentlyReleased:
            var parameters = recommendedParameters(in: library, types: [isTV ? .episode : .movie], limit: limit)
            parameters.maxPremiereDate = now
            if isTV {
                parameters.sortBy = [.premiereDate, .seriesSortName, .airedEpisodeOrder]
                parameters.sortOrder = [.descending, .ascending, .descending]
                parameters.isUnaired = false
            } else {
                parameters.sortBy = [.premiereDate, .sortName]
                parameters.sortOrder = [.descending, .ascending]
            }
            return try await send(Paths.getItems(parameters: parameters)).items.recommendedItems
        case .recentlyAdded:
            var parameters = recommendedParameters(in: library, types: [isTV ? .episode : .movie], limit: limit)
            parameters.sortBy = [.dateCreated]
            parameters.sortOrder = [.descending]
            return try await send(Paths.getItems(parameters: parameters)).items.recommendedItems
        case .topUnwatched:
            var parameters = recommendedParameters(in: library, types: [kind], limit: limit)
            parameters.isPlayed = false
            parameters.sortBy = [.communityRating]
            parameters.sortOrder = [.descending]
            return try await send(Paths.getItems(parameters: parameters)).items.recommendedItems
        case .suggestions:
            return try await suggestions(in: library, limit: limit)
        }
    }

    private func resumeItems(in library: Library, type: BaseItemKind, limit: Int) async throws -> [MediaItem] {
        var parameters = Paths.GetResumeItemsParameters(userID: userID)
        parameters.parentID = library.id
        parameters.limit = limit
        parameters.fields = Self.recommendedFields
        parameters.includeItemTypes = [type]
        parameters.enableUserData = true
        parameters.imageTypeLimit = 1
        parameters.enableTotalRecordCount = false
        return try await send(Paths.getResumeItems(parameters: parameters)).items.recommendedItems
    }

    private func nextUpItems(in library: Library, limit: Int) async throws -> [MediaItem] {
        var parameters = Paths.GetNextUpParameters(userID: userID)
        parameters.parentID = library.id
        parameters.limit = limit
        parameters.fields = Self.recommendedFields
        parameters.imageTypeLimit = 1
        parameters.enableUserData = true
        parameters.enableTotalRecordCount = false
        parameters.enableResumable = false
        // Wholphin's "rewatch in Next Up" setting, which is off unless changed.
        parameters.enableRewatching = false
        return try await send(Paths.getNextUp(parameters: parameters)).items.recommendedItems
    }

    /// Wholphin's suggestions (`SuggestionsWorker`): unwatched titles like the last three the
    /// user watched (by genre), plus random and newly added ones, mixed together.
    ///
    /// Wholphin works these out in the background and caches them; Anemone asks when the tab
    /// opens. Wholphin leaves the history in the server's default order, oldest first, so its
    /// "last three" are the first three ever watched; here they're the most recent.
    ///
    /// - Parameter order: puts the mix in order before it's cut to `limit`; shuffles by default.
    func suggestions(
        in library: Library,
        limit: Int = HomeRow.defaultLimit,
        order: @Sendable ([MediaItem]) -> [MediaItem] = { $0.shuffled() },
    ) async throws -> [MediaItem] {
        guard let kind = library.suggestionKind else { return [] }
        // Watched episodes stand for their series.
        var history = recommendedParameters(in: library, types: [kind == .series ? .episode : kind], limit: 20)
        history.isPlayed = true
        history.sortBy = [.datePlayed]
        history.sortOrder = [.descending]
        history.fields = [.genres]
        history.enableImages = false
        history.enableUserData = false
        var seeds: [String] = []
        var genreIDs: [String] = []
        for dto in try await send(Paths.getItems(parameters: history)).items ?? [] {
            guard let id = dto.seriesID ?? dto.id, !seeds.contains(id) else { continue }
            seeds.append(id)
            genreIDs += (dto.genreItems ?? []).compactMap(\.id).filter { !genreIDs.contains($0) }
            if seeds.count == 3 {
                break
            }
        }

        // Wholphin's mix: 40% like what was watched, 30% new, 30% random.
        let likeLimit = max(Int(Double(limit) * 0.4), 1)
        let otherLimit = max(Int(Double(limit) * 0.3), 1)
        async let alike = suggestionCandidates(
            in: library,
            kind: kind,
            limit: likeLimit,
            genreIDs: genreIDs,
            excluding: seeds,
        )
        async let fresh = suggestionCandidates(in: library, kind: kind, limit: otherLimit, newestFirst: true)
        async let random = suggestionCandidates(in: library, kind: kind, limit: otherLimit)
        var seen = Set(seeds)
        let mix = try await (alike + fresh + random).filter { seen.insert($0.id).inserted }
        return Array(order(mix).prefix(limit))
    }

    /// Unwatched titles for the suggestions: random ones, or the newest; with `genreIDs`, only
    /// in those genres, and none at all when there are none.
    private func suggestionCandidates(
        in library: Library,
        kind: BaseItemKind,
        limit: Int,
        genreIDs: [String]? = nil,
        excluding excluded: [String] = [],
        newestFirst: Bool = false,
    ) async throws -> [MediaItem] {
        if let genreIDs, genreIDs.isEmpty {
            return []
        }
        var parameters = recommendedParameters(in: library, types: [kind], limit: limit)
        parameters.isPlayed = false
        parameters.genreIDs = genreIDs
        parameters.excludeItemIDs = excluded.isEmpty ? nil : excluded
        parameters.sortBy = [newestFirst ? .dateCreated : .random]
        parameters.sortOrder = newestFirst ? [.descending] : nil
        return try await send(Paths.getItems(parameters: parameters)).items.recommendedItems
    }

    /// What every Recommended `/Items` request asks for.
    private func recommendedParameters(
        in library: Library,
        types: [BaseItemKind],
        limit: Int,
    ) -> Paths.GetItemsParameters {
        var parameters = Paths.GetItemsParameters(userID: userID)
        parameters.parentID = library.id
        parameters.includeItemTypes = types
        parameters.isRecursive = true
        parameters.limit = limit
        parameters.fields = Self.recommendedFields
        parameters.enableUserData = true
        parameters.enableImageTypes = [.primary, .thumb, .backdrop]
        parameters.imageTypeLimit = 1
        parameters.enableTotalRecordCount = false
        return parameters
    }

    /// The overview, for the header over the rows.
    private static let recommendedFields: [ItemFields] = [.overview]
}

private extension [BaseItemDto]? {
    var recommendedItems: [MediaItem] {
        (self ?? []).compactMap(MediaItem.init)
    }
}
