import Foundation

/// One row on the home page: what it shows and how its cards look. Ported from Wholphin's
/// `HomeRowConfig`, and stored as the same JSON (schema version 1), so settings move between
/// the two apps and the Wholphin server plugin.
public struct HomeRowConfig: Hashable, Sendable {
    /// What the row shows. Item IDs are kept in Jellyfin's compact form, without dashes.
    public enum Kind: Hashable, Sendable {
        /// Partly watched videos.
        case continueWatching
        /// The next episode of each series in progress.
        case nextUp
        /// Continue Watching and Next Up in one row, most recently watched first.
        case continueWatchingCombined
        case recentlyAdded(parentID: String)
        /// By premiere date, newest first.
        case recentlyReleased(parentID: String)
        case genres(parentID: String)
        case studios(parentID: String)
        /// The user's favourites of one item type, such as `Movie`, as Jellyfin names it.
        case favorite(itemKind: String)
        /// Live TV recordings in progress.
        case recordings
        /// Live TV programmes on now.
        case tvPrograms
        case tvChannels
        /// Picks for a movie or TV library, from what the user watched lately.
        case suggestions(parentID: String)
        /// The children of a library, collection or playlist.
        case byParent(parentID: String, recursive: Bool, sort: HomeRowSort?)
        /// An item query, mostly written by hand or by the server plugin.
        case getItems(name: String, filter: HomeGetItemsFilter)
        /// Items from another server plugin's endpoint.
        case customEndpoint(HomeCustomEndpoint)
    }

    public var kind: Kind
    public var viewOptions: HomeRowViewOptions

    /// - Parameter viewOptions: the kind's own default when `nil`, as in Wholphin.
    public init(_ kind: Kind, viewOptions: HomeRowViewOptions? = nil) {
        self.kind = kind
        self.viewOptions = viewOptions ?? kind.defaultViewOptions
    }

    /// The library or item the row is about, if any.
    public var parentID: String? {
        switch kind {
        case let .recentlyAdded(id), let .recentlyReleased(id), let .genres(id), let .studios(id),
             let .suggestions(id), let .byParent(id, _, _):
            id
        case let .getItems(_, filter):
            filter.parentID
        default:
            nil
        }
    }

    /// Whether the row shows what the user is watching, which Wholphin treats alike.
    public var isWatchingRow: Bool {
        switch kind {
        case .continueWatching, .nextUp, .continueWatchingCombined: true
        default: false
        }
    }
}

public extension HomeRowConfig.Kind {
    /// What a new row of this kind looks like: Wholphin's `genreDefault` for genres and studios,
    /// `liveTvDefault` for programmes and channels, and the plain default otherwise.
    var defaultViewOptions: HomeRowViewOptions {
        switch self {
        case .genres, .studios: .genreDefault
        case .tvPrograms, .tvChannels: .liveTVDefault
        default: HomeRowViewOptions()
        }
    }
}

/// How a row's cards look, as Wholphin's `HomeRowViewOptions`. Episodes have their own image
/// settings, so a mixed row can show posters for movies and stills for episodes.
public struct HomeRowViewOptions: Hashable, Sendable {
    /// How an image fills its card, as Wholphin's `PrefContentScale`, stored by its protobuf name.
    public enum ContentScale: String, Hashable, Sendable, CaseIterable {
        case fit = "FIT"
        case none = "NONE"
        case crop = "CROP"
        case fill = "FILL"
        case fillWidth = "Fill_WIDTH"
        case fillHeight = "FILL_HEIGHT"
    }

    /// A card's width over its height.
    public enum AspectRatio: String, Hashable, Sendable, CaseIterable {
        case tall = "TALL"
        case wide = "WIDE"
        case fourThree = "FOUR_THREE"
        case square = "SQUARE"

        public var ratio: Double {
            switch self {
            case .tall: 2.0 / 3.0
            case .wide: 16.0 / 9.0
            case .fourThree: 4.0 / 3.0
            case .square: 1
            }
        }
    }

    /// Which of an item's images a card shows.
    public enum ImageType: String, Hashable, Sendable, CaseIterable {
        case primary = "PRIMARY"
        case thumb = "THUMB"
    }

    /// Wholphin's `Cards.HEIGHT_2X3_DP`: a poster's height in Android density-independent pixels.
    public static let posterHeight = 172
    /// Wholphin's `Cards.HEIGHT_EPISODE`.
    public static let episodeHeight = 128
    /// Wholphin's `Cards.HEIGHT_LIVE_TV`.
    public static let liveTVHeight = 96

    /// The card's height in Android dp; Anemone scales it to points.
    public var heightDp = Self.posterHeight
    /// The gap between cards, in dp.
    public var spacing = 16
    public var contentScale = ContentScale.fill
    public var aspectRatio = AspectRatio.tall
    public var imageType = ImageType.primary
    public var showTitles = false
    /// Whether episodes show their series' art.
    public var useSeries = true
    public var episodeContentScale = ContentScale.fill
    public var episodeAspectRatio = AspectRatio.tall
    public var episodeImageType = ImageType.primary

    public init() {}

    /// Wholphin's default for genre and studio rows.
    public static let genreDefault: HomeRowViewOptions = {
        var options = HomeRowViewOptions()
        options.heightDp = episodeHeight
        options.aspectRatio = .wide
        return options
    }()

    /// Wholphin's default for Live TV rows.
    public static let liveTVDefault: HomeRowViewOptions = {
        var options = HomeRowViewOptions()
        options.heightDp = liveTVHeight
        options.aspectRatio = .wide
        options.contentScale = .fit
        return options
    }()

    /// Wholphin's "Use thumb images" shortcut: wide thumbs for everything.
    public var usingThumbs: HomeRowViewOptions {
        var options = self
        options.heightDp = Self.episodeHeight
        options.spacing = 20
        options.imageType = .thumb
        options.aspectRatio = .wide
        options.contentScale = .fit
        options.episodeImageType = .thumb
        options.episodeAspectRatio = .wide
        options.episodeContentScale = .fit
        return options
    }
}

/// A sort for a `byParent` row, as Wholphin's `SortAndDirection`. The field is Jellyfin's
/// `ItemSortBy` name, such as `SortName`.
public struct HomeRowSort: Hashable, Sendable, Codable {
    public enum Direction: String, Hashable, Sendable, Codable {
        case ascending = "Ascending"
        case descending = "Descending"
    }

    public var field: String
    public var direction: Direction

    public init(field: String, direction: Direction = .ascending) {
        self.field = field
        self.direction = direction
    }

    private enum CodingKeys: String, CodingKey {
        case field = "sort"
        case direction
    }
}

/// The item query behind a `getItems` row: a subset of Jellyfin's `GetItems` parameters, as
/// Wholphin's `HomeGetItemsFilter`. Kinds, sorts and orders use Jellyfin's names.
public struct HomeGetItemsFilter: Hashable, Sendable, Codable {
    public var sortBy: [String]?
    public var sortOrder: [String]?
    public var ids: [String]?
    public var minCommunityRating: Double?
    public var minCriticRating: Double?
    public var recursive: Bool?
    public var searchTerm: String?
    public var parentID: String?
    public var includeItemTypes: [String]?
    public var isFavorite: Bool?
    public var isPlayed: Bool?
    public var officialRatings: [String]?
    public var tags: [String]?
    public var years: [Int]?
    public var personIDs: [String]?
    public var minOfficialRating: String?
    public var hasOfficialRating: Bool?
    public var studioIDs: [String]?
    public var genreIDs: [String]?
    /// ISO 8601, as the Jellyfin SDKs write dates.
    public var minPremiereDate: String?
    public var maxPremiereDate: String?

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case sortBy, sortOrder, ids, minCommunityRating, minCriticRating, recursive, searchTerm
        case parentID = "parentId"
        case includeItemTypes, isFavorite, isPlayed, officialRatings, tags, years
        case personIDs = "personIds"
        case minOfficialRating, hasOfficialRating
        case studioIDs = "studioIds"
        case genreIDs = "genreIds"
        case minPremiereDate, maxPremiereDate
    }
}

/// A row from another plugin's endpoint, which answers with Jellyfin's item query result.
public struct HomeCustomEndpoint: Hashable, Sendable, Codable {
    /// A path relative to the server, such as `/HomeScreen/Section/Latest`.
    public var endpoint: String
    public var title: String
    public var headers: [KeyValueEntry]?
    public var query: [KeyValueEntry]?

    public init(endpoint: String, title: String, headers: [KeyValueEntry]? = nil, query: [KeyValueEntry]? = nil) {
        self.endpoint = endpoint
        self.title = title
        self.headers = headers
        self.query = query
    }
}

/// A list entry rather than a dictionary, because the server plugin stores its settings as XML.
public struct KeyValueEntry: Hashable, Sendable, Codable {
    public var key: String
    public var value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

/// The home page's rows, as Wholphin's `HomePageSettings`.
public struct HomePageSettings: Hashable, Sendable {
    /// The newest schema version this app reads, Wholphin's `SUPPORTED_HOME_PAGE_SETTINGS_VERSION`.
    public static let supportedVersion = 1

    public var rows: [HomeRowConfig]
    public var version: Int

    public init(rows: [HomeRowConfig], version: Int = Self.supportedVersion) {
        self.rows = rows
        self.version = version
    }
}

public enum HomeSettingsError: Error, Equatable {
    /// Written by a newer app, or missing its version.
    case unsupportedVersion(Int?)
}

/// Jellyfin item IDs: the server sends them without dashes, and Wholphin stores them with.
public enum JellyfinID {
    /// The compact form, lower case and without dashes. Anything that isn't a GUID is kept as is.
    public static func compact(_ id: String) -> String {
        let hex = id.replacingOccurrences(of: "-", with: "").lowercased()
        return isGUID(hex) ? hex : id
    }

    /// The dashed form Wholphin writes, such as `1dd1c2fd-2e1b-48e4-ba94-17a2350fe9cf`.
    public static func dashed(_ id: String) -> String {
        let hex = compact(id)
        guard isGUID(hex) else { return id }
        let characters = Array(hex)
        return [0 ..< 8, 8 ..< 12, 12 ..< 16, 16 ..< 20, 20 ..< 32]
            .map { String(characters[$0]) }
            .joined(separator: "-")
    }

    private static func isGUID(_ hex: String) -> Bool {
        hex.count == 32 && hex.allSatisfy(\.isHexDigit)
    }
}
