import Foundation

/// How a library grid is ordered, ported from Wholphin's `SortAndDirection`.
public struct LibrarySort: Hashable, Codable, Sendable {
    /// Wholphin's sort options. Raw values are Jellyfin's `ItemSortBy` names.
    public enum Field: String, Hashable, Codable, CaseIterable, Sendable {
        /// The server's own order, such as a playlist's.
        case `default` = "Default"
        case name = "SortName"
        case premiereDate = "PremiereDate"
        case dateCreated = "DateCreated"
        case dateLastContentAdded = "DateLastContentAdded"
        case datePlayed = "DatePlayed"
        case seriesDatePlayed = "SeriesDatePlayed"
        case communityRating = "CommunityRating"
        case criticRating = "CriticRating"
        case officialRating = "OfficialRating"
        case runtime = "Runtime"
        case playCount = "PlayCount"
        case albumArtist = "AlbumArtist"
        case random = "Random"
    }

    public enum Direction: String, Hashable, Codable, Sendable {
        case ascending
        case descending
    }

    public var field: Field
    public var direction: Direction

    public init(_ field: Field, _ direction: Direction = .ascending) {
        self.field = field
        self.direction = direction
    }

    /// Wholphin's default: by name, A to Z.
    public static let `default` = LibrarySort(.name)

    public var reversed: LibrarySort {
        LibrarySort(field, direction == .ascending ? .descending : .ascending)
    }

    /// Picking the current field again reverses the order, as in Wholphin's sort menu.
    public func choosing(_ field: Field) -> LibrarySort {
        field == self.field ? reversed : LibrarySort(field, direction)
    }
}

/// What a library grid is narrowed to, ported from Wholphin's `GetItemsFilter`. Empty sets and
/// `nil` mean "don't filter on this".
public struct LibraryFilter: Hashable, Codable, Sendable {
    /// The filters Wholphin offers, in its order.
    public enum Kind: Hashable, CaseIterable, Sendable {
        case played
        case favorite
        case genres
        case studios
        case communityRating
        case officialRating
        case videoType
        case year
        case decade
    }

    /// Wholphin's video filter. 4K, HD, SD and 3D map to the server's resolution flags; Blu-ray
    /// and DVD to its video types.
    public enum VideoType: String, Hashable, Codable, CaseIterable, Sendable {
        case fourK
        case highDefinition
        case standardDefinition
        case threeD
        case bluRay
        case dvd
    }

    public var played: Bool?
    public var favorite: Bool?
    /// Genre IDs.
    public var genres: Set<String> = []
    /// Studio IDs.
    public var studios: Set<String> = []
    /// From 1 to 10.
    public var minCommunityRating: Int?
    public var officialRatings: Set<String> = []
    public var videoTypes: Set<VideoType> = []
    public var years: Set<Int> = []
    /// Each decade by its first year, such as 1990.
    public var decades: Set<Int> = []

    public init() {}

    public var isEmpty: Bool {
        self == LibraryFilter()
    }

    /// How many kinds of filter are in use, for the filter button's badge.
    public var activeCount: Int {
        Kind.allCases.count(where: isActive)
    }

    public func isActive(_ kind: Kind) -> Bool {
        cleared(kind) != self
    }

    /// The decades covering `years`, by their first year, oldest first.
    public static func decades(of years: [Int]) -> [Int] {
        Set(years.map { $0 / 10 * 10 }).sorted()
    }

    public func cleared(_ kind: Kind) -> LibraryFilter {
        var filter = self
        switch kind {
        case .played: filter.played = nil
        case .favorite: filter.favorite = nil
        case .genres: filter.genres = []
        case .studios: filter.studios = []
        case .communityRating: filter.minCommunityRating = nil
        case .officialRating: filter.officialRatings = []
        case .videoType: filter.videoTypes = []
        case .year: filter.years = []
        case .decade: filter.decades = []
        }
        return filter
    }
}

/// A library grid's contents: which library, in what order, narrowed how.
public struct LibraryQuery: Hashable, Sendable {
    public var library: Library
    public var sort: LibrarySort
    public var filter: LibraryFilter

    public init(library: Library, sort: LibrarySort = .default, filter: LibraryFilter = LibraryFilter()) {
        self.library = library
        self.sort = sort
        self.filter = filter
    }
}

/// An item in a library grid.
public struct LibraryEntry: Hashable, Identifiable, Sendable {
    public let item: MediaItem
    /// The name the server sorts by, such as "matrix" for "The Matrix"; it picks the letter the
    /// alphabet bar highlights.
    public let sortName: String?

    public init(item: MediaItem, sortName: String?) {
        self.item = item
        self.sortName = sortName
    }

    public var id: MediaItem.ID {
        item.id
    }
}

/// One page of a library grid.
public struct LibraryPage: Sendable {
    public let items: [LibraryEntry]
    /// How many items match the query in all. Only asked for with the first page.
    public let totalCount: Int?

    public init(items: [LibraryEntry], totalCount: Int?) {
        self.items = items
        self.totalCount = totalCount
    }
}

/// A value to offer in a filter's list, such as a genre.
public struct FilterOption: Hashable, Identifiable, Sendable {
    /// What goes in the filter: an ID for genres and studios, otherwise the name.
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}
