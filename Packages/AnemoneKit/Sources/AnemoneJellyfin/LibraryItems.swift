import Foundation
import JellyfinAPI

/// What each kind of library's grid shows, following Wholphin's per-type library pages.
public extension Library {
    var sortFields: [LibrarySort.Field] {
        switch kind {
        case .shows:
            [
                .name, .premiereDate, .dateCreated, .dateLastContentAdded, .seriesDatePlayed,
                .communityRating, .criticRating, .officialRating, .random,
            ]
        case .music:
            [.name, .premiereDate, .dateCreated, .datePlayed, .albumArtist, .communityRating, .criticRating, .random]
        case .playlists:
            [.default] + Self.videoSortFields
        default:
            Self.videoSortFields
        }
    }

    var filterKinds: [LibraryFilter.Kind] {
        switch kind {
        case .shows: LibraryFilter.Kind.allCases
        default: LibraryFilter.Kind.allCases.filter { $0 != .studios }
        }
    }

    /// Wholphin's `MovieSortOptions` and `VideoSortOptions`, which are the same.
    private static let videoSortFields: [LibrarySort.Field] = [
        .name, .premiereDate, .dateCreated, .datePlayed, .communityRating, .criticRating, .officialRating,
        .runtime, .playCount, .random,
    ]

    /// Movie, TV and music libraries list their titles from every folder; the rest show their top
    /// level, folders included.
    internal var gridItemTypes: [BaseItemKind]? {
        switch kind {
        case .movies: [.movie]
        case .shows: [.series]
        case .music: [.musicAlbum]
        default: nil
        }
    }

    internal var isGridRecursive: Bool {
        switch kind {
        case .movies, .shows, .music, .playlists: true
        default: false
        }
    }
}

public extension JellyfinSession {
    /// One page of a library grid, from `startIndex`.
    func libraryItems(
        _ query: LibraryQuery,
        startIndex: Int,
        limit: Int,
        includeTotalCount: Bool = false,
    ) async throws -> LibraryPage {
        var parameters = query.itemsParameters(userID: userID)
        parameters.startIndex = startIndex
        parameters.limit = limit
        parameters.enableTotalRecordCount = includeTotalCount
        // Wholphin's `SlimItemFields`: the overview is for the details header and list layout.
        parameters.fields = [.sortName, .overview]
        parameters.enableImageTypes = [.primary, .thumb, .backdrop, .logo]
        parameters.imageTypeLimit = 1
        let result = try await send(Paths.getItems(parameters: parameters))
        let items = (result.items ?? []).compactMap(LibraryEntry.init)
        return LibraryPage(items: items, totalCount: includeTotalCount ? result.totalRecordCount ?? items.count : nil)
    }

    /// Where the alphabet bar jumps for `letter`: the first item filed under it, counted with the
    /// grid's own query so the index matches what's paged in. `#` stands for anything before A.
    ///
    /// - Parameter count: how many items the grid holds.
    /// - Returns: `count` when nothing is filed under the letter or past it, so there's nowhere to go.
    func position(of letter: Character, in query: LibraryQuery, count: Int) async throws -> Int {
        let ascending = query.sort.direction == .ascending
        // Descending, the letter's items start after everything filed under later letters.
        let bound = ascending ? LibraryJump.lowerBound(of: letter) : LibraryJump.upperBound(of: letter)
        guard let bound else { return 0 }
        var parameters = query.itemsParameters(userID: userID)
        parameters.nameLessThan = bound
        parameters.limit = 0
        parameters.enableTotalRecordCount = true
        parameters.enableUserData = false
        parameters.enableImages = false
        let before = try await send(Paths.getItems(parameters: parameters)).totalRecordCount ?? 0
        return min(max(ascending ? before : count - before, 0), count)
    }

    func genres(in library: Library) async throws -> [FilterOption] {
        let parameters = Paths.GetGenresParameters(parentID: library.id, userID: userID)
        return try await send(Paths.getGenres(parameters: parameters)).items.filterOptions
    }

    /// Wholphin only offers studios for TV libraries, and asks for those of series.
    func studios(in library: Library) async throws -> [FilterOption] {
        let parameters = Paths.GetStudiosParameters(parentID: library.id, includeItemTypes: [.series], userID: userID)
        return try await send(Paths.getStudios(parameters: parameters)).items.filterOptions
    }

    /// The age ratings used in the library, from least to most restrictive.
    func officialRatings(in library: Library) async throws -> [String] {
        async let filters = send(Paths.getQueryFiltersLegacy(parameters: .init(userID: userID, parentID: library.id)))
        async let ratings = send(Paths.getParentalRatings)
        let scores = try await Dictionary(
            ratings.compactMap { rating in rating.name.map { ($0, rating.ratingScore?.score ?? rating.value ?? 0) } },
        ) { first, _ in first }
        let used = try await filters.officialRatings ?? []
        // Stable, so ratings with the same score keep the server's order.
        return used.enumerated()
            .sorted { (scores[$0.element] ?? 0, $0.offset) < (scores[$1.element] ?? 0, $1.offset) }
            .map(\.element)
    }

    /// The production years in the library, oldest first.
    func years(in library: Library) async throws -> [Int] {
        let parameters = Paths.GetYearsParameters(
            sortOrder: [.ascending],
            parentID: library.id,
            sortBy: [.sortName],
            userID: userID,
        )
        return try await send(Paths.getYears(parameters: parameters)).items?.compactMap { $0.name.flatMap(Int.init) }
            .sorted() ?? []
    }
}

/// The alphabet bar's letters and the name bounds used to find them.
public enum LibraryJump {
    public static let letters: [Character] = Array("#ABCDEFGHIJKLMNOPQRSTUVWXYZ")

    /// The bar letter an item is filed under, from its sort name: `#` for digits, `nil` for
    /// anything else that isn't A to Z.
    public static func letter(for sortName: String?) -> Character? {
        guard let first = sortName?.first?.uppercased().first else { return nil }
        if first.isASCII, first.isNumber {
            return "#"
        }
        return letters.contains(first) && first != "#" ? first : nil
    }

    /// Items whose name sorts below this come before `letter`'s; `nil` for `#`, which starts the
    /// list. Jellyfin sort names are lower case.
    static func lowerBound(of letter: Character) -> String? {
        letter == "#" ? nil : letter.lowercased()
    }

    /// Items whose name sorts below this are `letter`'s or come before it.
    static func upperBound(of letter: Character) -> String? {
        guard let index = letters.firstIndex(of: letter) else { return nil }
        let next = letters.index(after: index)
        // After "z" comes "{" in code-point order.
        return next < letters.endIndex ? letters[next].lowercased() : "{"
    }

    /// Where a press of the remote's page up or down button moves focus from `index`, as
    /// Wholphin's `CardGrid` pages with the remote's skip buttons: six rows at a time, or more in
    /// a big library so its end stays a few presses away. Stays in the same column, and stops at
    /// the first and last items.
    public static func page(from index: Int, forward: Bool, columns: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let rows = switch count {
        case 25000...: 500
        case 7000...: 50
        case 2000...: 15
        default: 6
        }
        let step = max(columns, 1) * rows
        return min(max(index + (forward ? step : -step), 0), count - 1)
    }

    /// Where `letter`'s items start in a list that's all loaded and sorted by name, A to Z, such
    /// as a library's genres: the first one filed under the letter or a later one.
    ///
    /// - Returns: the list's count when nothing is filed under the letter or past it.
    public static func position(of letter: Character, in sortNames: [String?]) -> Int {
        guard let bound = lowerBound(of: letter) else { return 0 }
        return sortNames.firstIndex { ($0 ?? "").lowercased() >= bound } ?? sortNames.count
    }
}

extension LibraryQuery {
    /// Wholphin's `createGetItemsRequest` with its filter applied: everything but paging.
    func itemsParameters(userID: String) -> Paths.GetItemsParameters {
        var parameters = Paths.GetItemsParameters(userID: userID)
        parameters.parentID = library.id
        parameters.excludeItemIDs = [library.id]
        (parameters.sortBy, parameters.sortOrder) = sortParameters
        filter.apply(to: &parameters)
        switch scope {
        case .titles:
            parameters.includeItemTypes = library.gridItemTypes
            parameters.isRecursive = library.isGridRecursive
        case .collections:
            // As Wholphin's Collections tab asks: the server finds the box sets holding the
            // library's movies, though the box sets themselves live elsewhere.
            parameters.includeItemTypes = [.boxSet]
            parameters.isRecursive = true
        case let .genre(id):
            parameters.includeItemTypes = library.gridItemTypes
            parameters.isRecursive = true
            parameters.genreIDs = [id]
        case let .studio(id):
            parameters.includeItemTypes = library.gridItemTypes
            parameters.isRecursive = true
            parameters.studioIDs = [id]
        }
        return parameters
    }

    /// The chosen field, then name to break ties, then (for movies) year to tell remakes apart.
    private var sortParameters: ([ItemSortBy]?, [JellyfinAPI.SortOrder]?) {
        guard sort.field != .default, let field = ItemSortBy(rawValue: sort.field.rawValue) else { return (nil, nil) }
        var fields = [field]
        var orders = [sort.direction == .ascending ? JellyfinAPI.SortOrder.ascending : .descending]
        if sort.field != .name {
            fields.append(.sortName)
            orders.append(.ascending)
        }
        if library.kind == .movies {
            fields.append(.productionYear)
            orders.append(.ascending)
        }
        return (fields, orders)
    }
}

extension LibraryFilter {
    func apply(to parameters: inout Paths.GetItemsParameters) {
        parameters.isPlayed = played
        parameters.isFavorite = favorite
        parameters.genreIDs = genres.isEmpty ? nil : genres.sorted()
        parameters.studioIDs = studios.isEmpty ? nil : studios.sorted()
        parameters.minCommunityRating = minCommunityRating.map(Double.init)
        parameters.officialRatings = officialRatings.isEmpty ? nil : officialRatings.sorted()
        let allYears = years.union(decades.flatMap { $0 ..< $0 + 10 })
        parameters.years = allYears.isEmpty ? nil : allYears.sorted()
        guard !videoTypes.isEmpty else { return }
        parameters.isIs4K = videoTypes.contains(.fourK) ? true : nil
        // As in Wholphin, HD wins if both HD and SD are picked.
        parameters.isHd = if videoTypes.contains(.highDefinition) {
            true
        } else if videoTypes.contains(.standardDefinition) {
            false
        } else {
            nil
        }
        parameters.isIs3D = videoTypes.contains(.threeD) ? true : nil
        let discs = [(VideoType.bluRay, JellyfinAPI.VideoType.bluRay), (.dvd, .dvd)]
            .compactMap { videoTypes.contains($0) ? $1 : nil }
        parameters.videoTypes = discs.isEmpty ? nil : discs
    }
}

extension LibraryEntry {
    init?(_ dto: BaseItemDto) {
        guard let details = ItemDetails(dto) else { return nil }
        self.init(item: details.item, sortName: dto.sortName, details: details)
    }
}

private extension [BaseItemDto]? {
    var filterOptions: [FilterOption] {
        (self ?? []).compactMap { dto in
            guard let id = dto.id, let name = dto.name else { return nil }
            return FilterOption(id: id, name: name)
        }
    }
}
