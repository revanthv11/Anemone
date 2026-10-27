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
        case .recentlyAdded: String(localized: "Recently Added", bundle: .module)
        case .recentlyReleased: String(localized: "Recently Released", bundle: .module)
        case .suggestions: String(localized: "Suggestions", bundle: .module)
        case .genres: String(localized: "Genres", bundle: .module)
        case .studios: String(localized: "Studios", bundle: .module)
        case .tvChannels: String(localized: "Channels", bundle: .module)
        case .tvPrograms: String(localized: "Watch Live", bundle: .module)
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
        let present = Set(libraries.flatMap { kinds(in: $0.kind) } + ["Person"])
        return order.filter(present.contains)
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
        "Movie": String(localized: "Movies", bundle: .module),
        "Series": String(localized: "TV Shows", bundle: .module),
        "Episode": String(localized: "Episodes", bundle: .module),
        "BoxSet": String(localized: "Collections", bundle: .module),
        "Person": String(localized: "People", bundle: .module),
        "TvChannel": String(localized: "Channels", bundle: .module),
        "MusicAlbum": String(localized: "Albums", bundle: .module),
        "MusicArtist": String(localized: "Artists", bundle: .module),
        "Audio": String(localized: "Songs", bundle: .module),
        "MusicVideo": String(localized: "Music Videos", bundle: .module),
        "Playlist": String(localized: "Playlists", bundle: .module),
        "Video": String(localized: "Videos", bundle: .module),
        "Photo": String(localized: "Photos", bundle: .module),
        "PhotoAlbum": String(localized: "Photo Albums", bundle: .module),
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
        let parent = parentID.flatMap { id in libraries.first(where: { $0.id == id })?.name ?? names[id] }
        return parent.flatMap(title(naming:)) ?? fixedTitle
    }

    /// The title of a row that names the library or item it's from, as a whole sentence rather
    /// than "Genres" + " in " + "Movies", so a translation can put the name where its language
    /// needs it. `nil` for rows whose title never names one.
    private func title(naming parent: String) -> String? {
        switch kind {
        case .recentlyAdded: String(localized: "Recently Added in \(parent)", bundle: .module)
        case .recentlyReleased: String(localized: "Recently Released in \(parent)", bundle: .module)
        case .genres: String(localized: "Genres in \(parent)", bundle: .module)
        case .studios: String(localized: "Studios in \(parent)", bundle: .module)
        case .suggestions: String(localized: "Suggestions for \(parent)", bundle: .module)
        case .byParent: parent
        default: nil
        }
    }

    /// The title when the row names no library or item.
    private var fixedTitle: String {
        switch kind {
        case .continueWatching, .continueWatchingCombined: String(localized: "Continue Watching", bundle: .module)
        case .nextUp: String(localized: "Next Up", bundle: .module)
        case .recentlyAdded: String(localized: "Recently Added", bundle: .module)
        case .recentlyReleased: String(localized: "Recently Released", bundle: .module)
        case .genres: String(localized: "Genres", bundle: .module)
        case .studios: String(localized: "Studios", bundle: .module)
        case let .favorite(itemKind):
            String(localized: "Favorite \(HomeFavoriteKind.pluralName(itemKind))", bundle: .module)
        case .recordings: String(localized: "Active Recordings", bundle: .module)
        case .tvPrograms: String(localized: "Watch Live", bundle: .module)
        case .tvChannels: String(localized: "Channels", bundle: .module)
        case .suggestions: String(localized: "Suggestions", bundle: .module)
        case .byParent: String(localized: "Collection", bundle: .module)
        case let .getItems(name, _): name
        case let .customEndpoint(endpoint): endpoint.title
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
    /// row, keeping its look, and any other such rows go. When there's a combined row already,
    /// the separate rows just go, where Wholphin would add a second combined row.
    func combiningWatchingRows() -> [HomeRowConfig] {
        if contains(where: { $0.kind == .continueWatchingCombined }) {
            return filter { $0.kind != .continueWatching && $0.kind != .nextUp }
        }
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
