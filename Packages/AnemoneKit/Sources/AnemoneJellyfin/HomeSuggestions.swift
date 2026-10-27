import AnemoneCore
import Foundation
import JellyfinAPI

/// Suggestions for a movie or TV library, ported from Wholphin's `SuggestionsWorker` and
/// `SuggestionService`. Wholphin works them out in the background every twelve hours; Anemone
/// works them out when the row first loads and keeps the picks as long, so the row doesn't
/// reshuffle each time Home shows.
extension JellyfinSession {
    func suggestions(for parentID: String, context: HomeRowContext) async throws -> [MediaItem] {
        let itemKind = try await suggestionKind(for: parentID, context: context)
        let key = "\(parentID)/\(itemKind.rawValue)"
        let cache = context.options.cache
        let ids: [String]
        if let cached = await cache.suggestions(for: key) {
            ids = cached
        } else {
            ids = try await pickSuggestions(in: parentID, kind: itemKind, count: context.limit)
            await cache.setSuggestions(ids, for: key)
        }
        guard !ids.isEmpty else { return [] }
        var parameters = Paths.GetItemsParameters(userID: userID)
        parameters.ids = ids
        parameters.fields = Self.homeFields + [.primaryImageAspectRatio]
        // The server returns them in its own order; keep the picks' order.
        let items = try await items(parameters)
        return ids.compactMap { id in items.first { $0.id == id } }
    }

    /// Movies for a movie library, series for a TV library (`getTypeForCollection`).
    private func suggestionKind(for parentID: String, context: HomeRowContext) async throws -> BaseItemKind {
        let kind = if let library = context.library(parentID) {
            library.kind
        } else {
            try await Library(send(Paths.getItem(itemID: parentID, userID: userID)))?.kind
        }
        switch kind {
        case .movies: return .movie
        case .shows: return .series
        default: throw HomeRowError.noSuggestions
        }
    }

    /// Wholphin's mix: 40% unwatched items sharing a genre with the last three things watched,
    /// 30% at random and 30% newly added, shuffled.
    func pickSuggestions(in parentID: String, kind: BaseItemKind, count: Int) async throws -> [String] {
        let historyKind: BaseItemKind = kind == .series ? .episode : kind
        var played = suggestionParameters(parentID, historyKind, sortBy: .datePlayed, limit: 20)
        played.isPlayed = true
        played.sortOrder = [.descending]
        played.fields = [.genres]
        let history = try await send(Paths.getItems(parameters: played)).items ?? []
        // The last three things watched, counting a series once.
        var seen = Set<String>()
        let seeds = history.filter { ($0.seriesID ?? $0.id).map { seen.insert($0).inserted } ?? false }.prefix(3)
        let seedIDs = Set(seeds.compactMap { $0.seriesID ?? $0.id })
        let genreIDs = Array(Set(seeds.flatMap { $0.genreItems?.compactMap(\.id) ?? [] }))

        var contextual = suggestionParameters(parentID, kind, sortBy: .random, limit: max(count * 4 / 10, 1))
        contextual.genreIDs = genreIDs
        contextual.excludeItemIDs = Array(seedIDs)
        let random = suggestionParameters(parentID, kind, sortBy: .random, limit: max(count * 3 / 10, 1))
        var fresh = suggestionParameters(parentID, kind, sortBy: .dateCreated, limit: max(count * 3 / 10, 1))
        fresh.sortOrder = [.descending]

        async let contextualIDs = genreIDs.isEmpty ? [] : suggestionIDs(contextual)
        async let randomIDs = suggestionIDs(random)
        async let freshIDs = suggestionIDs(fresh)
        var picked = Set<String>()
        let all = try await (contextualIDs + freshIDs + randomIDs)
            .filter { !seedIDs.contains($0) && picked.insert($0).inserted }
        return Array(all.shuffled().prefix(count))
    }

    private func suggestionParameters(
        _ parentID: String,
        _ kind: BaseItemKind,
        sortBy: ItemSortBy,
        limit: Int,
    ) -> Paths.GetItemsParameters {
        var parameters = Paths.GetItemsParameters(userID: userID)
        parameters.parentID = parentID
        parameters.includeItemTypes = [kind]
        parameters.isRecursive = true
        parameters.isPlayed = false
        parameters.sortBy = [sortBy]
        parameters.limit = limit
        parameters.enableTotalRecordCount = false
        parameters.imageTypeLimit = 0
        return parameters
    }

    private func suggestionIDs(_ parameters: Paths.GetItemsParameters) async throws -> [String] {
        try await (send(Paths.getItems(parameters: parameters)).items ?? []).compactMap(\.id)
    }
}
