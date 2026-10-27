import AnemoneCore
import Foundation
import Get
import JellyfinAPI

/// Fetching each kind of row, ported from Wholphin's `HomeDataService.fetchDataForRow`.
extension JellyfinSession {
    func homeRowData(_ config: HomeRowConfig, context: HomeRowContext) async throws -> HomeRowData {
        switch config.kind {
        case .continueWatching, .nextUp, .continueWatchingCombined:
            try await HomeRowData(items: watchingRow(config.kind, context: context))
        case .genres, .studios:
            try await categoryRow(config.kind, context: context)
        case .recordings, .tvPrograms, .tvChannels:
            try await HomeRowData(items: liveTVRow(config.kind, context: context))
        case let .favorite(itemKind):
            try await HomeRowData(items: favorites(itemKind, limit: context.limit))
        case let .suggestions(parentID):
            try await HomeRowData(items: suggestions(for: parentID, context: context))
        case let .customEndpoint(endpoint):
            try await HomeRowData(items: customEndpointItems(endpoint))
        default:
            try await itemRow(config.kind, context: context)
        }
    }

    // MARK: Watching

    private func watchingRow(_ kind: HomeRowConfig.Kind, context: HomeRowContext) async throws -> [MediaItem] {
        switch kind {
        case .continueWatching:
            return try await resumeEntries(limit: context.limit).map(\.item)
        case .nextUp:
            return try await nextUpEntries(context: context).map(\.item)
        default:
            async let resume = resumeEntries(limit: context.limit)
            async let nextUp = nextUpEntries(context: context)
            let combined = try await combinedWatching(resume: resume, nextUp: nextUp, cache: context.options.cache)
            return Array(combined.prefix(context.limit))
        }
    }

    /// Wholphin's `getResume`, episodes included.
    func resumeEntries(limit: Int) async throws -> [WatchingEntry] {
        let parameters = Paths.GetResumeItemsParameters(
            userID: userID,
            limit: limit,
            fields: Self.homeFields,
            mediaTypes: [.video],
            imageTypeLimit: 1,
            enableTotalRecordCount: false,
        )
        return try await (send(Paths.getResumeItems(parameters: parameters)).items ?? []).compactMap(WatchingEntry.init)
    }

    /// Wholphin's `getNextUp`: partly watched episodes are left to Continue Watching, and series the
    /// user removed stay out until they play one of its episodes again.
    func nextUpEntries(context: HomeRowContext, now: Date = .now) async throws -> [WatchingEntry] {
        let maxDays = context.options.maxDaysNextUp
        let parameters = Paths.GetNextUpParameters(
            userID: userID,
            limit: context.limit,
            fields: Self.homeFields,
            imageTypeLimit: 1,
            enableUserData: true,
            nextUpDateCutoff: maxDays > 0 ? now.addingTimeInterval(-Double(maxDays) * 86400) : nil,
            enableTotalRecordCount: false,
            enableResumable: false,
            enableRewatching: context.options.enableRewatchingNextUp,
        )
        let entries = try await (send(Paths.getNextUp(parameters: parameters)).items ?? [])
            .compactMap(WatchingEntry.init)
        return entries.filter { context.removed.allows(seriesID: $0.item.episode?.seriesID, lastPlayed: $0.lastPlayed) }
    }

    // MARK: Items

    /// Rows that are an item query: Recently Added and Released, `byParent` and `getItems`.
    private func itemRow(_ kind: HomeRowConfig.Kind, context: HomeRowContext) async throws -> HomeRowData {
        switch kind {
        case let .recentlyAdded(parentID):
            return try await HomeRowData(items: recentlyAdded(in: parentID, limit: context.limit))
        case let .byParent(parentID, recursive, sort):
            // The parent's name is the title; a parent that's gone fails the row with a 404.
            async let parent = item(id: parentID)
            var parameters = itemParameters(limit: context.limit)
            parameters.parentID = parentID
            parameters.isRecursive = recursive
            (parameters.sortBy, parameters.sortOrder) = Self.byParentSort(sort)
            let items = try await items(parameters)
            return try await HomeRowData(items: items, title: parent.name)
        case let .getItems(_, filter):
            var parameters = itemParameters(limit: context.limit)
            filter.apply(to: &parameters)
            return try await HomeRowData(items: items(parameters))
        default:
            guard case let .recentlyReleased(parentID) = kind else { return HomeRowData(cards: []) }
            return try await HomeRowData(items: items(Self.recentlyReleasedParameters(
                userID: userID,
                parentID: parentID,
                limit: context.limit,
            )))
        }
    }

    /// Wholphin's Recently Released: newest premiere first, then by series and episode, nothing
    /// that hasn't aired.
    static func recentlyReleasedParameters(
        userID: String,
        parentID: String,
        limit: Int,
        now: Date = .now,
    ) -> Paths.GetItemsParameters {
        var parameters = Paths.GetItemsParameters(userID: userID)
        parameters.parentID = parentID
        parameters.limit = limit
        parameters.sortBy = [.premiereDate, .seriesSortName, .airedEpisodeOrder]
        parameters.sortOrder = [.descending, .ascending, .descending]
        parameters.fields = homeFields
        parameters.isRecursive = true
        parameters.maxPremiereDate = now
        parameters.isUnaired = false
        parameters.imageTypeLimit = 1
        parameters.enableTotalRecordCount = false
        return parameters
    }

    /// Wholphin's `ByParent` sort: the field, then name to break ties; random picks shuffle
    /// within a name order.
    static func byParentSort(_ sort: HomeRowSort?) -> ([ItemSortBy]?, [JellyfinAPI.SortOrder]?) {
        guard let sort, let field = ItemSortBy(rawValue: sort.field) else { return (nil, nil) }
        let direction: JellyfinAPI.SortOrder = sort.direction == .ascending ? .ascending : .descending
        if field == .random {
            return ([.sortName, .random], [.ascending, direction])
        }
        if field == .sortName {
            return ([field], [direction])
        }
        return ([field, .sortName], [direction, .ascending])
    }

    private func itemParameters(limit: Int) -> Paths.GetItemsParameters {
        var parameters = Paths.GetItemsParameters(userID: userID)
        parameters.limit = limit
        parameters.fields = Self.homeFields + [.childCount]
        parameters.imageTypeLimit = 1
        parameters.enableTotalRecordCount = false
        return parameters
    }

    func items(_ parameters: Paths.GetItemsParameters) async throws -> [MediaItem] {
        try await (send(Paths.getItems(parameters: parameters)).items ?? []).compactMap(MediaItem.init)
    }

    // MARK: Favourites

    /// Wholphin's favourites row. People have an endpoint of their own. Wholphin asks `/Artists`
    /// for artists, which jellyfin-sdk-swift marks deprecated, so they go through `/Items` too.
    private func favorites(_ itemKind: String, limit: Int) async throws -> [MediaItem] {
        let result: BaseItemDtoQueryResult
        switch BaseItemKind(rawValue: itemKind) {
        case .person:
            var parameters = Paths.GetPersonsParameters(limit: limit, fields: Self.homeFields, isFavorite: true)
            parameters.userID = userID
            parameters.enableImages = true
            parameters.enableImageTypes = [.primary]
            result = try await send(Paths.getPersons(parameters: parameters))
        case let .some(kind):
            var parameters = itemParameters(limit: limit)
            parameters.isRecursive = true
            parameters.includeItemTypes = [kind]
            parameters.isFavorite = true
            result = try await send(Paths.getItems(parameters: parameters))
        case nil:
            return []
        }
        return (result.items ?? []).compactMap(MediaItem.init)
    }

    // MARK: Live TV

    private func liveTVRow(_ kind: HomeRowConfig.Kind, context: HomeRowContext) async throws -> [MediaItem] {
        let source = context.options.liveTV
        return switch kind {
        case .recordings: try await source.recordingsInProgress(limit: context.limit)
        case .tvPrograms: try await source.programsOnNow(limit: context.limit)
        default: try await source.channels(limit: context.limit)
        }
    }

    /// Extra fields for cards and the home header.
    static let homeFields: [ItemFields] = [.overview]
}

/// What Settings › Home needs from the server.
public extension JellyfinSession {
    /// The user's collections (`BoxSet`) or playlists (`Playlist`), by name, for a row of their
    /// items, as Wholphin's Add Row searches for one.
    func homeParentChoices(itemKind: String) async throws -> [MediaItem] {
        guard let kind = BaseItemKind(rawValue: itemKind) else { return [] }
        var parameters = Paths.GetItemsParameters(userID: userID)
        parameters.includeItemTypes = [kind]
        parameters.isRecursive = true
        parameters.sortBy = [.sortName]
        parameters.limit = 200
        parameters.enableImages = false
        return try await items(parameters)
    }

    /// Items by ID, in the order asked for; IDs the server doesn't know are left out.
    func mediaItems(ids: [String]) async throws -> [MediaItem] {
        guard !ids.isEmpty else { return [] }
        var parameters = Paths.GetItemsParameters(userID: userID)
        parameters.ids = ids
        parameters.enableImages = false
        let items = try await items(parameters)
        return ids.compactMap { id in items.first { $0.id == id } }
    }
}

extension HomeGetItemsFilter {
    /// Wholphin's `asGetItemsRequest`. Unknown kinds, sorts and orders are dropped. Unlike
    /// Wholphin, the premiere-date bounds are sent too.
    func apply(to parameters: inout Paths.GetItemsParameters) {
        parameters.sortBy = sortBy?.compactMap(ItemSortBy.init(rawValue:))
        parameters.sortOrder = sortOrder?.compactMap(JellyfinAPI.SortOrder.init(rawValue:))
        parameters.ids = ids?.map(JellyfinID.compact)
        parameters.minCommunityRating = minCommunityRating
        parameters.minCriticRating = minCriticRating
        parameters.isRecursive = recursive
        parameters.searchTerm = searchTerm
        parameters.parentID = parentID.map(JellyfinID.compact)
        parameters.includeItemTypes = includeItemTypes?.compactMap(BaseItemKind.init(rawValue:))
        parameters.isFavorite = isFavorite
        parameters.isPlayed = isPlayed
        parameters.officialRatings = officialRatings
        parameters.tags = tags
        parameters.years = years
        parameters.personIDs = personIDs?.map(JellyfinID.compact)
        parameters.minOfficialRating = minOfficialRating
        parameters.hasOfficialRating = hasOfficialRating
        parameters.studioIDs = studioIDs?.map(JellyfinID.compact)
        parameters.genreIDs = genreIDs?.map(JellyfinID.compact)
        parameters.minPremiereDate = minPremiereDate.flatMap(Self.date)
        parameters.maxPremiereDate = maxPremiereDate.flatMap(Self.date)
    }

    private static func date(_ text: String) -> Date? {
        (try? Date(text, strategy: .iso8601)) ?? RemovedFromNextUp.date(from: text)
    }
}
