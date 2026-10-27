import Foundation
import JellyfinAPI

/// One of the user's libraries (a Jellyfin "user view").
public struct Library: Hashable, Identifiable, Sendable {
    /// The library's content type, from its Jellyfin collection type.
    public enum Kind: Hashable, Sendable {
        case movies
        case shows
        case music
        case musicVideos
        case homeVideos
        case photos
        case collections
        case playlists
        case liveTV
        case folders
        /// No collection type: a library of mixed content.
        case mixed
        case books
        case trailers
        case other
    }

    public let id: String
    public let name: String
    public let kind: Kind
    /// A Live TV recording folder, which Wholphin's `CollectionFolderLiveTv` lists without
    /// looking into subfolders and with the video sort options, whatever its kind.
    public var isRecordingFolder = false

    public init(id: String, name: String, kind: Kind) {
        self.id = id
        self.name = name
        self.kind = kind
    }

    /// Whether Anemone lists this library, matching Wholphin's `supportedCollectionTypes`.
    public var isSupported: Bool {
        switch kind {
        case .books, .trailers, .other:
            false
        default:
            true
        }
    }

    /// Whether the default home page has a Recently Added row for it. Wholphin gives Live TV a
    /// "Watch live" row instead, which comes with the other Live TV rows.
    public var hasRecentlyAddedRow: Bool {
        isSupported && kind != .liveTV
    }
}

extension Library {
    init?(_ dto: BaseItemDto) {
        guard let id = dto.id else { return nil }
        self.init(id: id, name: dto.name ?? "", kind: Kind(dto.collectionType))
    }
}

private extension Library.Kind {
    init(_ type: CollectionType?) {
        guard let type else {
            self = .mixed
            return
        }
        self = Self.byCollectionType[type] ?? .other
    }

    static let byCollectionType: [CollectionType: Self] = [
        .movies: .movies,
        .tvshows: .shows,
        .music: .music,
        .musicvideos: .musicVideos,
        .homevideos: .homeVideos,
        .photos: .photos,
        .boxsets: .collections,
        .playlists: .playlists,
        .livetv: .liveTV,
        .folders: .folders,
        .books: .books,
        .trailers: .trailers,
    ]
}
