import Foundation
import JellyfinAPI

/// One row of the Favorites page: the user's favourites of one type.
public struct FavoritesSection: Hashable, Identifiable, Sendable {
    public let kind: MediaItem.Kind
    public let items: [ItemDetails]

    public init(kind: MediaItem.Kind, items: [ItemDetails]) {
        self.kind = kind
        self.items = items
    }

    public var id: MediaItem.Kind {
        kind
    }

    /// Ported from Wholphin's `favoriteOptions`: the types the Favorites page shows, in its order.
    /// Live TV channels come with Live TV, and music artists and photo albums with music and
    /// photos, in Phase 5.
    public static let kinds: [MediaItem.Kind] = [
        .movie,
        .series,
        .episode,
        .collection,
        .person,
        .musicAlbum,
        .audio,
        .musicVideo,
        .playlist,
        .video,
        .photo,
    ]

    /// Ported from Wholphin's `possibleFavoriteTypes`: the types worth asking about for these
    /// libraries, in the page's order. People belong to no library, so they're always asked about.
    public static func kinds(for libraries: [Library]) -> [MediaItem.Kind] {
        let available = Set(libraries.flatMap(\.kind.itemKinds)).union([.person])
        return kinds.filter(available.contains)
    }
}

/// The Favorites page's rows, and the types whose row couldn't be loaded.
public struct FavoritesContent: Hashable, Sendable {
    /// Rows with at least one favourite, in the page's order.
    public let sections: [FavoritesSection]
    public let failedKinds: [MediaItem.Kind]

    public init(sections: [FavoritesSection], failedKinds: [MediaItem.Kind] = []) {
        self.sections = sections
        self.failedKinds = failedKinds
    }

    /// The page with one type's row loaded again, as after a favourite of that type changed. The
    /// row goes when `items` is empty, and a new row comes in at its place in the page's order.
    public func replacing(_ kind: MediaItem.Kind, with items: [ItemDetails]) -> FavoritesContent {
        var sections = sections.filter { $0.kind != kind }
        if !items.isEmpty {
            let order = FavoritesSection.kinds
            let rank = { (kind: MediaItem.Kind) in order.firstIndex(of: kind) ?? order.count }
            let index = sections.firstIndex { rank($0.kind) > rank(kind) } ?? sections.count
            sections.insert(FavoritesSection(kind: kind, items: items), at: index)
        }
        return FavoritesContent(sections: sections, failedKinds: failedKinds.filter { $0 != kind })
    }
}

/// Ported from Wholphin's `FavoritesViewModel`.
public extension JellyfinSession {
    /// The user's favourites of one type, by name, as Wholphin sorts them by default. Only the
    /// first `limit`, since the page shows them in a row.
    func favorites(of kind: MediaItem.Kind, limit: Int = 100) async throws -> [ItemDetails] {
        if kind == .person {
            let parameters = Paths.GetPersonsParameters(
                limit: limit,
                fields: Self.favoriteFields,
                isFavorite: true,
                enableUserData: true,
                userID: userID,
            )
            return try await send(Paths.getPersons(parameters: parameters)).items.favoriteDetails
        }
        guard let type = kind.itemKind else { return [] }
        let parameters = Paths.GetItemsParameters(
            userID: userID,
            limit: limit,
            isRecursive: true,
            sortOrder: [.ascending],
            fields: Self.favoriteFields,
            includeItemTypes: [type],
            isFavorite: true,
            sortBy: [.sortName],
            enableUserData: true,
        )
        return try await send(Paths.getItems(parameters: parameters)).items.favoriteDetails
    }

    /// Every row of the Favorites page for these libraries, asked for at once. Empty rows are
    /// left out. A row that fails is left out too and named in `failedKinds`, as Wholphin keeps
    /// a failed tab; a revoked token, or every row failing, throws.
    func favorites(for libraries: [Library]) async throws -> FavoritesContent {
        let kinds = FavoritesSection.kinds(for: libraries)
        let results = await withTaskGroup(of: (MediaItem.Kind, Result<[ItemDetails], any Error>).self) { group in
            for kind in kinds {
                group.addTask {
                    do {
                        return try await (kind, .success(favorites(of: kind)))
                    } catch {
                        return (kind, .failure(error))
                    }
                }
            }
            return await group.reduce(into: [:]) { $0[$1.0] = $1.1 }
        }
        var sections: [FavoritesSection] = []
        var failed: [MediaItem.Kind] = []
        var firstError: (any Error)?
        for kind in kinds {
            switch results[kind] {
            case let .success(items)?:
                if !items.isEmpty {
                    sections.append(FavoritesSection(kind: kind, items: items))
                }
            case let .failure(error)?:
                if error as? SessionError == .signedOut {
                    throw SessionError.signedOut
                }
                firstError = firstError ?? error
                failed.append(kind)
            case nil:
                break
            }
        }
        if let firstError, failed.count == kinds.count {
            throw firstError
        }
        return FavoritesContent(sections: sections, failedKinds: failed)
    }

    /// For the page's header and cards: the focused item's overview, card shapes and counts.
    private static let favoriteFields: [ItemFields] = [.overview, .primaryImageAspectRatio, .childCount]
}

private extension Library.Kind {
    /// The types a library of this kind holds, from Wholphin's `CollectionType.baseItemKinds`.
    var itemKinds: [MediaItem.Kind] {
        switch self {
        case .movies: [.movie]
        case .shows: [.series, .season, .episode]
        case .music: [.audio, .musicAlbum]
        case .musicVideos: [.musicVideo]
        // Wholphin means videos and photos here, but its `when` branch returns only its last
        // list, photo albums.
        case .homeVideos: [.video, .photo]
        case .photos: [.photo]
        case .collections: [.collection]
        case .playlists: [.playlist]
        // Wholphin offers no favourites for these; libraries without a type can hold anything.
        case .folders, .mixed: [.movie, .series, .episode, .video]
        case .liveTV, .books, .trailers, .other: []
        }
    }
}

private extension MediaItem.Kind {
    /// The server's name for the type, for queries; `nil` for kinds Anemone groups together.
    var itemKind: BaseItemKind? {
        switch self {
        case .movie: .movie
        case .series: .series
        case .season: .season
        case .episode: .episode
        case .collection: .boxSet
        case .playlist: .playlist
        case .person: .person
        case .video: .video
        case .musicVideo: .musicVideo
        case .musicAlbum: .musicAlbum
        case .musicArtist: .musicArtist
        case .audio: .audio
        case .photo: .photo
        case .folder, .other: nil
        }
    }
}

private extension [BaseItemDto]? {
    var favoriteDetails: [ItemDetails] {
        (self ?? []).compactMap(ItemDetails.init)
    }
}
