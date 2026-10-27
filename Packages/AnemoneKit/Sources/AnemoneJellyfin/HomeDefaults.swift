import AnemoneCore
import Foundation

public extension HomePageSettings {
    /// Wholphin's default home page (`HomeSettingsService.createDefault`): Continue Watching and
    /// Next Up combined, then Recently Added for each library, or "Watch live" for Live TV.
    static func defaultRows(for libraries: [Library]) -> [HomeRowConfig] {
        let libraryRows = libraries.filter(\.isSupported).map { library in
            library.kind == .liveTV
                ? HomeRowConfig(.tvPrograms)
                : HomeRowConfig(.recentlyAdded(parentID: library.id), viewOptions: .defaults(for: library.kind))
        }
        return [HomeRowConfig(.continueWatchingCombined)] + libraryRows
    }
}

public extension HomeRowViewOptions {
    /// Wholphin's `viewOptionsForCollectionType`: square music, wide photos and videos.
    static func defaults(for kind: Library.Kind) -> HomeRowViewOptions {
        var options = HomeRowViewOptions()
        switch kind {
        case .music:
            options.heightDp = episodeHeight
            options.aspectRatio = .square
        case .photos, .homeVideos, .musicVideos, .trailers:
            options.heightDp = episodeHeight
            options.aspectRatio = .wide
        case .liveTV:
            options = .liveTVDefault
        default:
            break
        }
        return options
    }
}

/// The row types the Add Row page offers for a library, from Wholphin's `getSupportedRowTypes`.
public enum HomeLibraryRowType: String, Hashable, Sendable, CaseIterable {
    case recentlyAdded
    case recentlyReleased
    case suggestions
    case genres
    case studios
    case tvChannels
    case tvPrograms

    public static func available(for library: Library) -> [Self] {
        switch library.kind {
        case .liveTV: [.tvChannels, .tvPrograms]
        case .shows: [.recentlyAdded, .recentlyReleased, .suggestions, .genres, .studios]
        case .movies: [.recentlyAdded, .recentlyReleased, .suggestions, .genres]
        default: [.recentlyAdded, .recentlyReleased, .genres]
        }
    }

    public var title: String {
        switch self {
        case .recentlyAdded: "Recently Added"
        case .recentlyReleased: "Recently Released"
        case .suggestions: "Suggestions"
        case .genres: "Genres"
        case .studios: "Studios"
        case .tvChannels: "Channels"
        case .tvPrograms: "Watch Live"
        }
    }

    /// A new row of this type, as Wholphin's `HomeSettingsViewModel.addRow` makes it.
    public func row(for library: Library) -> HomeRowConfig {
        let options = HomeRowViewOptions.defaults(for: library.kind)
        return switch self {
        case .recentlyAdded: HomeRowConfig(.recentlyAdded(parentID: library.id), viewOptions: options)
        case .recentlyReleased: HomeRowConfig(.recentlyReleased(parentID: library.id), viewOptions: options)
        case .suggestions: HomeRowConfig(.suggestions(parentID: library.id), viewOptions: options)
        case .genres: HomeRowConfig(.genres(parentID: library.id))
        case .studios: HomeRowConfig(.studios(parentID: library.id))
        case .tvChannels: HomeRowConfig(.tvChannels)
        case .tvPrograms: HomeRowConfig(.tvPrograms)
        }
    }
}

/// Item types that can have a favourites row, in Wholphin's order (`favoriteOptions`), by the
/// names Jellyfin gives them.
public enum HomeFavoriteKind {
    /// The types the user's libraries can hold, plus people, who aren't in any library.
    public static func available(for libraries: [Library]) -> [String] {
        let kinds = Set(libraries.flatMap { kinds(in: $0.kind) } + ["Person"])
        return order.filter(kinds.contains)
    }

    /// "Movies" for `Movie`, as Wholphin's `formatTypeName`.
    public static func pluralName(_ kind: String) -> String {
        names[kind] ?? kind
    }

    static let order = [
        "Movie", "Series", "Episode", "BoxSet", "Person", "TvChannel", "MusicAlbum", "MusicArtist", "Audio",
        "MusicVideo", "Playlist", "Video", "Photo", "PhotoAlbum",
    ]

    private static let names = [
        "Movie": "Movies", "Series": "TV Shows", "Episode": "Episodes", "BoxSet": "Collections",
        "Person": "People", "TvChannel": "Channels", "MusicAlbum": "Albums", "MusicArtist": "Artists",
        "Audio": "Songs", "MusicVideo": "Music Videos", "Playlist": "Playlists", "Video": "Videos",
        "Photo": "Photos", "PhotoAlbum": "Photo Albums",
    ]

    private static func kinds(in kind: Library.Kind) -> [String] {
        kindsByLibrary[kind] ?? []
    }

    private static let kindsByLibrary: [Library.Kind: [String]] = [
        .movies: ["Movie"],
        .shows: ["Series", "Episode"],
        .music: ["MusicAlbum", "MusicArtist", "Audio"],
        .musicVideos: ["MusicVideo"],
        .homeVideos: ["Video", "Photo"],
        .photos: ["Photo", "PhotoAlbum"],
        .collections: ["BoxSet"],
        .playlists: ["Playlist"],
        .liveTV: ["TvChannel"],
    ]
}

public extension HomeRowConfig {
    /// The row's title, as Wholphin's `HomeSettingsService.resolve` words it. `names` holds the
    /// names of items that aren't libraries, such as a collection shown by a `byParent` row.
    func title(libraries: [Library], names: [String: String] = [:]) -> String {
        let wording = titleWording
        guard let joiner = wording.joiner, let id = parentID,
              let name = libraries.first(where: { $0.id == id })?.name ?? names[id]
        else { return wording.text }
        return joiner.isEmpty ? name : wording.text + joiner + name
    }

    /// A fixed title, or the start of one that names the library: "Genres" + " in " + "Movies".
    /// An empty joiner means the parent's name alone.
    private var titleWording: (text: String, joiner: String?) {
        switch kind {
        case .continueWatching, .continueWatchingCombined: ("Continue Watching", nil)
        case .nextUp: ("Next Up", nil)
        case .recentlyAdded: ("Recently Added", " in ")
        case .recentlyReleased: ("Recently Released", " in ")
        case .genres: ("Genres", " in ")
        case .studios: ("Studios", " in ")
        case let .favorite(itemKind): ("Favorite \(HomeFavoriteKind.pluralName(itemKind))", nil)
        case .recordings: ("Active Recordings", nil)
        case .tvPrograms: ("Watch Live", nil)
        case .tvChannels: ("Channels", nil)
        case .suggestions: ("Suggestions", " for ")
        case .byParent: ("Collection", "")
        case let .getItems(name, _): (name, nil)
        case let .customEndpoint(endpoint): (endpoint.title, nil)
        }
    }

    /// Stable, readable IDs for rows, used for focus memory and accessibility identifiers such as
    /// `card.continueWatching.<item>`. Repeats get a number.
    static func rowIDs(for rows: [HomeRowConfig]) -> [String] {
        var seen: [String: Int] = [:]
        return rows.map { row in
            let base = row.idBase
            let count = (seen[base] ?? 0) + 1
            seen[base] = count
            return count == 1 ? base : "\(base).\(count)"
        }
    }

    private var idBase: String {
        switch kind {
        case .continueWatching, .continueWatchingCombined: "continueWatching"
        case .nextUp: "nextUp"
        case let .recentlyAdded(id): "recentlyAdded.\(id)"
        case let .recentlyReleased(id): "recentlyReleased.\(id)"
        case let .genres(id): "genres.\(id)"
        case let .studios(id): "studios.\(id)"
        case let .favorite(itemKind): "favorite.\(itemKind)"
        case .recordings: "recordings"
        case .tvPrograms: "tvPrograms"
        case .tvChannels: "tvChannels"
        case let .suggestions(id): "suggestions.\(id)"
        case let .byParent(id, _, _): "byParent.\(id)"
        case .getItems: "getItems"
        case .customEndpoint: "customEndpoint"
        }
    }
}

public extension [HomeRowConfig] {
    /// Wholphin's "Combine" action: the first Continue Watching or Next Up row becomes the combined
    /// row, keeping its look, and any other such rows go.
    func combiningWatchingRows() -> [HomeRowConfig] {
        guard let index = firstIndex(where: { $0.kind == .continueWatching || $0.kind == .nextUp }) else {
            return self
        }
        var rows = self
        rows[index] = HomeRowConfig(.continueWatchingCombined, viewOptions: rows[index].viewOptions)
        return rows.enumerated()
            .filter { $0.offset == index || ($0.element.kind != .continueWatching && $0.element.kind != .nextUp) }
            .map(\.element)
    }

    /// Wholphin's "Split" action: the combined row becomes Continue Watching followed by Next Up,
    /// both with its look.
    func splittingWatchingRows() -> [HomeRowConfig] {
        guard let index = firstIndex(where: { $0.kind == .continueWatchingCombined }) else { return self }
        var rows = self
        let options = rows[index].viewOptions
        rows[index] = HomeRowConfig(.continueWatching, viewOptions: options)
        rows.insert(HomeRowConfig(.nextUp, viewOptions: options), at: index + 1)
        return rows
    }
}
