#if ANEMONE_SEERR
    import Foundation

    /// What Seerr knows a title as, matching Jellyfin's movies, series and people.
    public enum SeerrMediaKind: String, Hashable, Sendable {
        case movie
        case series = "tv"
        case person

        /// Seerr's `mediaType`.
        init?(mediaType: String?) {
            guard let mediaType, let kind = Self(rawValue: mediaType) else { return nil }
            self = kind
        }
    }

    /// How much of a title the Jellyfin server has, as Seerr tracks it. Ported from Wholphin's
    /// `SeerrAvailability`, whose values come from Seerr's `server/constants/media.ts`.
    public enum SeerrAvailability: Int, Comparable, Hashable, Sendable {
        /// Not requested, or nothing known.
        case unknown = 1
        case pending
        case processing
        case partiallyAvailable
        case available
        case blocklisted
        case deleted

        init(status: Int?) {
            self = status.flatMap(Self.init(rawValue:)) ?? .unknown
        }

        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// Where a request stands. Ported from Wholphin's `RequestStatus`.
    public enum SeerrRequestStatus: Int, Comparable, Hashable, Sendable {
        case unknown = 0
        case pending
        case approved
        case declined
        case failed
        case completed

        init(status: Int?) {
            self = status.flatMap(Self.init(rawValue:)) ?? .unknown
        }

        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// A movie, series or person found through Seerr, which may or may not be on the Jellyfin
    /// server. Ported from Wholphin's `DiscoverItem`.
    public struct DiscoverItem: Hashable, Identifiable, Sendable {
        /// The TMDB ID; a movie and a series can share one.
        public var tmdbID: Int
        public var kind: SeerrMediaKind
        public var title: String
        /// For a credit, the character or the job.
        public var subtitle: String?
        public var overview: String?
        public var availability: SeerrAvailability
        /// As Seerr sends it, such as `2024-05-17`.
        public var releaseDate: String?
        public var posterURL: URL?
        public var backdropURL: URL?
        /// The item on the Jellyfin server, once it's there (the 4K copy's, if there is one).
        public var jellyfinItemID: String?

        public init(
            tmdbID: Int,
            kind: SeerrMediaKind,
            title: String,
            subtitle: String? = nil,
            overview: String? = nil,
            availability: SeerrAvailability = .unknown,
            releaseDate: String? = nil,
            posterURL: URL? = nil,
            backdropURL: URL? = nil,
            jellyfinItemID: String? = nil,
        ) {
            self.tmdbID = tmdbID
            self.kind = kind
            self.title = title
            self.subtitle = subtitle
            self.overview = overview
            self.availability = availability
            self.releaseDate = releaseDate
            self.posterURL = posterURL
            self.backdropURL = backdropURL
            self.jellyfinItemID = jellyfinItemID
        }

        /// Unique in a row that mixes movies and series, unlike the TMDB ID.
        public var id: String {
            "\(kind.rawValue)-\(tmdbID)"
        }

        public var year: Int? {
            guard let releaseDate, releaseDate.count >= 4 else { return nil }
            return Int(releaseDate.prefix(4))
        }
    }

    /// A season of a series as Seerr sees it: what the server has, and what's been asked for.
    /// The fields of Wholphin's `RequestSeason`.
    public struct SeerrSeason: Hashable, Identifiable, Sendable {
        public var number: Int
        public var name: String?
        public var episodeCount: Int?
        /// What the server has, or will have once a request goes through.
        public var availability: SeerrAvailability
        /// The furthest any request for it has got.
        public var requestStatus: SeerrRequestStatus
        /// Whether it can be asked for now: it isn't on the server or on its way, or the user's own
        /// request for it is still pending or was declined.
        public var isRequestable: Bool

        public var id: Int {
            number
        }

        public init(
            number: Int,
            name: String? = nil,
            episodeCount: Int? = nil,
            availability: SeerrAvailability = .unknown,
            requestStatus: SeerrRequestStatus = .unknown,
            isRequestable: Bool = true,
        ) {
            self.number = number
            self.name = name
            self.episodeCount = episodeCount
            self.availability = availability
            self.requestStatus = requestStatus
            self.isRequestable = isRequestable
        }
    }

    /// A request for a title.
    public struct SeerrRequest: Hashable, Identifiable, Sendable {
        public var id: Int
        public var status: SeerrRequestStatus
        public var is4K: Bool
        /// The Seerr user who asked.
        public var requestedBy: Int?
        /// For a series: each requested season's own status.
        public var seasons: [Int: SeerrRequestStatus]

        public init(
            id: Int,
            status: SeerrRequestStatus,
            is4K: Bool = false,
            requestedBy: Int? = nil,
            seasons: [Int: SeerrRequestStatus] = [:],
        ) {
            self.id = id
            self.status = status
            self.is4K = is4K
            self.requestedBy = requestedBy
            self.seasons = seasons
        }
    }

    /// A request on the Requests page, with the title it's for.
    public struct SeerrRequestedItem: Hashable, Identifiable, Sendable {
        public var request: SeerrRequest
        public var item: DiscoverItem

        public init(request: SeerrRequest, item: DiscoverItem) {
            self.request = request
            self.item = item
        }

        public var id: Int {
            request.id
        }
    }

    /// A movie's or series' page: the details Seerr has, its requests and, for a series, its
    /// seasons.
    public struct DiscoverDetails: Hashable, Sendable {
        public var item: DiscoverItem
        public var tagline: String?
        public var genres: [String]
        /// In minutes.
        public var runtime: Int?
        /// Out of 10, from TMDB.
        public var rating: Double?
        public var requests: [SeerrRequest]
        /// Its seasons, specials included, for a series; empty for a movie.
        public var seasons: [SeerrSeason]
        /// The same seasons in 4K, which are requested separately.
        public var seasons4K: [SeerrSeason]

        public init(
            item: DiscoverItem,
            tagline: String? = nil,
            genres: [String] = [],
            runtime: Int? = nil,
            rating: Double? = nil,
            requests: [SeerrRequest] = [],
            seasons: [SeerrSeason] = [],
            seasons4K: [SeerrSeason] = [],
        ) {
            self.item = item
            self.tagline = tagline
            self.genres = genres
            self.runtime = runtime
            self.rating = rating
            self.requests = requests
            self.seasons = seasons
            self.seasons4K = seasons4K
        }
    }

    /// The signed-in Seerr user.
    public struct SeerrUser: Hashable, Sendable {
        public var id: Int
        public var name: String
        public var permissions: SeerrPermissions

        public init(id: Int, name: String, permissions: SeerrPermissions) {
            self.id = id
            self.name = name
            self.permissions = permissions
        }
    }

    /// The Seerr server's settings that change what the app offers.
    public struct SeerrServerSettings: Hashable, Sendable {
        /// Whether Seerr serves TMDB's images itself (`/imageproxy/tmdb`).
        public var cachesImages: Bool
        public var allows4KMovies: Bool
        public var allows4KSeries: Bool

        public init(cachesImages: Bool = false, allows4KMovies: Bool = false, allows4KSeries: Bool = false) {
            self.cachesImages = cachesImages
            self.allows4KMovies = allows4KMovies
            self.allows4KSeries = allows4KSeries
        }
    }
#endif
