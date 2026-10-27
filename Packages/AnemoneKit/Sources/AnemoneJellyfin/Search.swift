import Foundation
import Get
import JellyfinAPI

/// A kind of item Search looks for, each with its own row of results, in the order of Wholphin's
/// `allSearchableTypes`. Raw values are Jellyfin's item types, so a saved choice of kinds stays
/// readable. Live TV channels and programs join with the Live TV guide.
public enum SearchKind: String, CaseIterable, Codable, Hashable, Sendable {
    case movie = "Movie"
    case series = "Series"
    case episode = "Episode"
    case collection = "BoxSet"
    case person = "Person"
    case musicAlbum = "MusicAlbum"
    case musicArtist = "MusicArtist"
    case audio = "Audio"
    case musicVideo = "MusicVideo"
    case playlist = "Playlist"
    case video = "Video"
    case photo = "Photo"
    case photoAlbum = "PhotoAlbum"

    /// Wholphin's `SEARCH_LIMIT`: results asked for per row, and for the combined grid.
    public static let resultLimit = 50

    /// The kinds worth searching for with these libraries, as in Wholphin's
    /// `determineSearchableTypes`: people always, everything else only when one of the libraries
    /// holds that kind, and never the excluded kinds.
    public static func searchable(in libraries: [Library], excluding excluded: Set<Self> = []) -> [Self] {
        let held = Set(libraries.flatMap(\.searchKinds))
        return allCases.filter { kind in
            !excluded.contains(kind) && (kind == .person || held.contains(kind))
        }
    }

    var itemKind: BaseItemKind {
        switch self {
        case .movie: .movie
        case .series: .series
        case .episode: .episode
        case .collection: .boxSet
        case .person: .person
        case .musicAlbum: .musicAlbum
        case .musicArtist: .musicArtist
        case .audio: .audio
        case .musicVideo: .musicVideo
        case .playlist: .playlist
        case .video: .video
        case .photo: .photo
        case .photoAlbum: .photoAlbum
        }
    }
}

public extension Library {
    /// The kinds of item this library can hold, from Wholphin's `CollectionType.baseItemKinds`.
    ///
    /// Two changes from Wholphin: a home-videos library holds videos, photos and photo albums
    /// (Wholphin's list keeps only photo albums, because each `listOf` replaces the one before),
    /// and a library of mixed content or folders can hold movies, series, episodes and videos
    /// (Wholphin searches none of them there).
    var searchKinds: [SearchKind] {
        switch kind {
        case .movies: [.movie]
        case .shows: [.series, .episode]
        case .homeVideos: [.video, .photo, .photoAlbum]
        case .music: [.audio, .musicArtist, .musicAlbum]
        case .musicVideos: [.musicVideo]
        case .collections: [.collection]
        case .playlists: [.playlist]
        case .photos: [.photo, .photoAlbum]
        case .mixed, .folders: [.movie, .series, .episode, .video]
        case .liveTV, .books, .trailers, .other: []
        }
    }
}

/// Search requests, ported from Wholphin's `SearchViewModel` and `SearchForViewModel`.
public extension JellyfinSession {
    /// Items of one kind whose names match `term`, most relevant first. People and music artists
    /// have endpoints of their own; everything else is an item query, as in Wholphin's
    /// `searchType`.
    func search(_ term: String, for kind: SearchKind, limit: Int = SearchKind.resultLimit) async throws
        -> [ItemDetails]
    {
        let items: [BaseItemDto]? = switch kind {
        case .person:
            try await send(Paths.getPersons(parameters: Paths.GetPersonsParameters(
                limit: limit,
                searchTerm: term,
                fields: Self.searchFields,
                enableUserData: true,
                userID: userID,
            ))).items
        case .musicArtist:
            try await send(Self.artists(Paths.GetArtistsParameters(
                limit: limit,
                searchTerm: term,
                fields: Self.searchFields,
                enableUserData: true,
                userID: userID,
                enableTotalRecordCount: false,
            ))).items
        default:
            try await send(Paths.getItems(parameters: searchParameters(term, kinds: [kind], limit: limit))).items
        }
        return SearchRelevance.sorted((items ?? []).compactMap(ItemDetails.init), for: term)
    }

    /// Wholphin's combined results: one query for all the kinds at once, most relevant first.
    /// No kinds finds nothing, without asking: an item query without types would match every type.
    func search(_ term: String, forAll kinds: [SearchKind], limit: Int = SearchKind.resultLimit) async throws
        -> [ItemDetails]
    {
        guard !kinds.isEmpty else { return [] }
        let parameters = searchParameters(term, kinds: kinds, limit: limit)
        let items = try await send(Paths.getItems(parameters: parameters)).items ?? []
        return SearchRelevance.sorted(items.compactMap(ItemDetails.init), for: term)
    }

    /// What `SearchForViewModel` suggests before anything is typed: the items of one kind with
    /// the newest content, such as collections and playlists to add to.
    func latestItems(of kind: SearchKind, limit: Int = 25) async throws -> [ItemDetails] {
        var parameters = Paths.GetItemsParameters(userID: userID)
        parameters.isRecursive = true
        parameters.includeItemTypes = [kind.itemKind]
        parameters.fields = Self.searchFields
        parameters.sortBy = [.dateLastContentAdded]
        parameters.sortOrder = [.descending]
        parameters.limit = limit
        parameters.enableUserData = true
        return try await send(Paths.getItems(parameters: parameters)).items?.compactMap(ItemDetails.init) ?? []
    }

    private func searchParameters(_ term: String, kinds: [SearchKind], limit: Int) -> Paths.GetItemsParameters {
        var parameters = Paths.GetItemsParameters(userID: userID)
        parameters.searchTerm = term
        parameters.isRecursive = true
        parameters.includeItemTypes = kinds.map(\.itemKind)
        parameters.fields = Self.searchFields
        parameters.limit = limit
        parameters.enableUserData = true
        parameters.enableTotalRecordCount = false
        return parameters
    }

    /// `GET /Artists`, as `Paths.getArtists` sends it. The SDK marks that deprecated, following
    /// Jellyfin's API description, but it's still how Wholphin finds artists by name, and nothing
    /// replaces it; built here so the build stays free of the warning.
    private static func artists(_ parameters: Paths.GetArtistsParameters) -> Request<BaseItemDtoQueryResult> {
        Request(path: "/Artists", method: "GET", query: parameters.asQuery, id: "GetArtists")
    }

    /// Fields for result cards and their badges: overview, image shape and item counts.
    private static let searchFields: [ItemFields] = [.overview, .primaryImageAspectRatio, .childCount]
}

/// How well a result's name matches what was typed, lower being better. Ported from Wholphin's
/// `SearchRelevance`: an exact match, then a prefix, then a word start, then anywhere, then a
/// near miss by edit distance. A query written `/pattern/` or `/pattern/i` matches as a regular
/// expression. Within each band, series come first, then movies, collections and episodes.
public enum SearchRelevance {
    public static func score(name: String?, kind: MediaItem.Kind, query: String) -> Int {
        Matcher(query).score(name: name, kind: kind)
    }

    /// `items` best match first; equal scores keep the server's order. The query is prepared
    /// once for all of them, so a regular expression is compiled once, not for every item.
    public static func sorted(_ items: [ItemDetails], for query: String) -> [ItemDetails] {
        let matcher = Matcher(query)
        return items.enumerated()
            .map { (score: matcher.score(name: $0.element.item.name, kind: $0.element.item.kind), $0) }
            .sorted { ($0.score, $0.1.offset) < ($1.score, $1.1.offset) }
            .map(\.1.element)
    }

    /// A query ready to score names with: lowercased text, or a compiled regular expression.
    private enum Matcher {
        case text(String)
        /// `nil` when the pattern doesn't compile, which matches nothing.
        case regex(Regex<AnyRegexOutput>?)

        init(_ query: String) {
            if let (pattern, ignoresCase) = SearchRelevance.regex(in: query) {
                self = .regex((try? Regex(pattern))?.ignoresCase(ignoresCase))
            } else {
                self = .text(query.lowercased())
            }
        }

        func score(name: String?, kind: MediaItem.Kind) -> Int {
            guard let name = name?.lowercased() else { return Int.max }
            let band = switch self {
            case let .text(query):
                SearchRelevance.band(name, query: query)
            case let .regex(regex):
                (try? regex?.firstMatch(in: name)) != nil ? 250 : 400
            }
            return band + typeBonus(kind)
        }
    }

    private static func band(_ name: String, query: String) -> Int {
        if name == query {
            0
        } else if name.hasPrefix(query) {
            100
        } else if name.contains(" \(query)") {
            200
        } else if name.contains(query) {
            300
        } else {
            fuzzyScore(name, query)
        }
    }

    /// The pattern of a `/pattern/` or `/pattern/i` query.
    private static func regex(in query: String) -> (String, Bool)? {
        guard query.count > 2, query.hasPrefix("/") else { return nil }
        if query.hasSuffix("/i"), query.count > 3 {
            return (String(query.dropFirst().dropLast(2)), true)
        }
        if query.hasSuffix("/") {
            return (String(query.dropFirst().dropLast()), false)
        }
        return nil
    }

    private static func fuzzyScore(_ name: String, _ query: String) -> Int {
        let length = max(name.count, query.count)
        guard length > 0 else { return 400 }
        let similarity = 1 - Double(editDistance(Array(name), Array(query))) / Double(length)
        return if similarity >= 0.8 {
            350
        } else if similarity >= 0.6 {
            375
        } else {
            400
        }
    }

    /// Levenshtein distance, a row at a time.
    private static func editDistance(_ first: [Character], _ second: [Character]) -> Int {
        var previous = Array(0 ... second.count)
        for (row, letter) in first.enumerated() {
            var current = [row + 1]
            for (column, other) in second.enumerated() {
                let cost = letter == other
                    ? previous[column]
                    : 1 + min(previous[column + 1], current[column], previous[column])
                current.append(cost)
            }
            previous = current
        }
        return previous[second.count]
    }

    private static func typeBonus(_ kind: MediaItem.Kind) -> Int {
        switch kind {
        case .series: 0
        case .movie: 1
        case .collection: 2
        case .episode: 10
        default: 5
        }
    }
}

/// What the user searched for lately, newest first, so Search can offer it again before anything
/// is typed. Anemone's own: Wholphin doesn't keep a history.
public struct RecentSearches: Codable, Hashable, Sendable {
    public static let limit = 10

    public private(set) var terms: [String]

    public init(terms: [String] = []) {
        self.terms = terms
    }

    /// Puts `term`, trimmed, first. An earlier copy differing only in case goes, as does the
    /// oldest past the limit. Blank terms aren't kept.
    public mutating func add(_ term: String) {
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        remove(term)
        terms.insert(term, at: 0)
        terms = Array(terms.prefix(Self.limit))
    }

    public mutating func remove(_ term: String) {
        terms.removeAll { $0.caseInsensitiveCompare(term) == .orderedSame }
    }

    public mutating func clear() {
        terms = []
    }
}
