import Foundation
import JellyfinAPI

/// An artist credited on an album or song, to open the artist's page.
public struct MusicArtistLink: Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    /// The artist, to open their page.
    public var item: MediaItem {
        MediaItem(id: id, name: name, kind: .musicArtist)
    }
}

/// A song, album or artist with what music pages show beyond `ItemDetails`: the artists, the
/// album, the track number and whether there are lyrics. Ported from what Wholphin's `BaseItem`
/// and `AudioItem` read for music.
public struct MusicItem: Hashable, Identifiable, Sendable {
    public var details: ItemDetails
    /// The album's main artist, as the server names it.
    public var albumArtist: String?
    /// Every artist on a song, or on any of an album's songs.
    public var artists: [String]
    public var albumArtistLinks: [MusicArtistLink]
    public var artistLinks: [MusicArtistLink]
    /// For songs.
    public var albumName: String?
    /// For songs.
    public var albumID: String?
    /// The album's cover, which songs show.
    public var albumImage: ItemImage?
    public var trackNumber: Int?
    public var discNumber: Int?
    public var hasLyrics: Bool
    /// The audio streams of the song's first version, for choosing an AC3 transcode.
    public var audioStreams: [AudioStreamInfo]
    /// For albums and artists: how many songs they have.
    public var songCount: Int?

    public init(
        details: ItemDetails,
        albumArtist: String? = nil,
        artists: [String] = [],
        albumArtistLinks: [MusicArtistLink] = [],
        artistLinks: [MusicArtistLink] = [],
        albumName: String? = nil,
        albumID: String? = nil,
        albumImage: ItemImage? = nil,
        trackNumber: Int? = nil,
        discNumber: Int? = nil,
        hasLyrics: Bool = false,
        audioStreams: [AudioStreamInfo] = [],
        songCount: Int? = nil,
    ) {
        self.details = details
        self.albumArtist = albumArtist
        self.artists = artists
        self.albumArtistLinks = albumArtistLinks
        self.artistLinks = artistLinks
        self.albumName = albumName
        self.albumID = albumID
        self.albumImage = albumImage
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.hasLyrics = hasLyrics
        self.audioStreams = audioStreams
        self.songCount = songCount
    }

    public var id: MediaItem.ID {
        details.id
    }

    public var item: MediaItem {
        details.item
    }

    /// The artists joined, as Wholphin's `artistsString` shows them; `nil` when there are none.
    public var artistNames: String? {
        let names = artists.filter { !$0.isBlank }
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    /// The square art cards and Now Playing show: the item's own, or for a song, its album's.
    public var coverImage: ItemImage? {
        item.squareImage ?? albumImage
    }

    /// What a card shows under the title, as Wholphin's `BaseItem.subtitle` has it for music: an
    /// album's artist and year (upstream `90a2d6d`), a song's album and artists.
    public var subtitle: String? {
        switch item.kind {
        case .musicAlbum:
            Self.albumSubtitle(albumArtist: albumArtist, artists: artists, year: item.year)
        case .audio:
            [albumName, artistNames].joinedNotBlank(" - ")
        default:
            item.year.map(String.init)
        }
    }

    /// Ported from Wholphin's album subtitle (upstream `90a2d6d`): the album artist, or the
    /// song artists when there's none, then the year, joined with " - ". Blank parts are left
    /// out; `nil` when nothing is left.
    public static func albumSubtitle(albumArtist: String?, artists: [String], year: Int?) -> String? {
        let artist = albumArtist.flatMap { $0.isBlank ? nil : $0 }
            ?? artists.filter { !$0.isBlank }.joined(separator: ", ")
        return [artist, year.map(String.init)].joinedNotBlank(" - ")
    }

    /// Whether an album's songs come from several artists, so its song list names each one, as
    /// Wholphin's album page does.
    public var isVariousArtists: Bool {
        let all = artists + [albumArtist].compactMap(\.self) + albumArtistLinks.map(\.name)
        return all.contains { $0.lowercased() == "various artists" } || artists.count > 1
    }
}

/// An audio stream in a song's file, for the AC3 choice.
public struct AudioStreamInfo: Hashable, Sendable {
    public var codec: String?
    public var channels: Int?

    public init(codec: String?, channels: Int?) {
        self.codec = codec
        self.channels = channels
    }
}

/// A music genre in a library, with art from one of its albums.
public struct MusicGenre: Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public var image: ItemImage?

    public init(id: String, name: String, image: ItemImage? = nil) {
        self.id = id
        self.name = name
        self.image = image
    }
}

/// What a music library tab lists, as Wholphin's `CollectionFolderMusic` tabs do.
public enum MusicList: Hashable, Sendable {
    case albums(library: Library.ID)
    /// A genre's albums, from the Genres tab.
    case genre(String, library: Library.ID)
    /// Wholphin lists every artist (`/Artists`), not only album artists.
    case artists(library: Library.ID)
    case songs(library: Library.ID)

    /// Wholphin's sort options for each list (`AlbumSortOptions`, `ArtistSortOptions`,
    /// `SongSortOptions`).
    public var sortFields: [MusicSort.Field] {
        switch self {
        case .albums, .genre:
            [.name, .premiereDate, .dateCreated, .datePlayed, .albumArtist, .communityRating, .criticRating, .random]
        case .artists:
            [.name, .premiereDate, .dateCreated, .datePlayed, .communityRating, .criticRating, .random]
        case .songs:
            [
                .name, .premiereDate, .album, .albumArtist, .artist, .dateCreated, .datePlayed, .communityRating,
                .criticRating, .playCount, .runtime, .random,
            ]
        }
    }
}

/// How a music list is ordered: Wholphin's music sort options, which add album and artist to
/// the library sorts.
public struct MusicSort: Hashable, Codable, Sendable {
    /// Raw values are Jellyfin's `ItemSortBy` names.
    public enum Field: String, Hashable, Codable, CaseIterable, Sendable {
        case name = "SortName"
        case premiereDate = "PremiereDate"
        case album = "Album"
        case albumArtist = "AlbumArtist"
        case artist = "Artist"
        case dateCreated = "DateCreated"
        case datePlayed = "DatePlayed"
        case communityRating = "CommunityRating"
        case criticRating = "CriticRating"
        case playCount = "PlayCount"
        case runtime = "Runtime"
        case random = "Random"
    }

    public var field: Field
    public var direction: LibrarySort.Direction

    public init(_ field: Field, _ direction: LibrarySort.Direction = .ascending) {
        self.field = field
        self.direction = direction
    }

    public static let `default` = MusicSort(.name)

    /// Picking the current field again reverses the order, as in Wholphin's sort menu.
    public func choosing(_ field: Field) -> MusicSort {
        guard field == self.field else { return MusicSort(field, direction) }
        return MusicSort(field, direction == .ascending ? .descending : .ascending)
    }
}

/// Where a queue of songs comes from: Wholphin's `getPagerForAlbum`, `getPagerForArtist` and
/// `getPagerForPlaylist`, and Play All on a library's albums, songs or genres.
public enum MusicSource: Hashable, Sendable {
    case album(MediaItem.ID)
    case artist(MediaItem.ID)
    case playlist(MediaItem.ID)
    case library(Library.ID)
    /// The Songs tab's songs, in the order the tab shows them.
    case songs(library: Library.ID, sort: MusicSort)
    case genre(String, library: Library.ID)

    /// Whether it can hold more songs than a queue takes, so shuffling it asks the server for a
    /// random order instead of fetching it all.
    public var isLarge: Bool {
        switch self {
        case .library, .songs, .artist, .genre: true
        case .album, .playlist: false
        }
    }

    /// Whether the server picks a new random order for each request, so a queue from it comes
    /// in one request: pages would repeat some songs and miss others.
    public var isRandomOrder: Bool {
        switch self {
        case let .songs(_, sort): sort.field == .random
        case .album, .artist, .playlist, .library, .genre: false
        }
    }
}

/// One page of a music list.
public struct MusicPage: Sendable {
    public let items: [MusicItem]
    /// Only asked for with the first page.
    public let totalCount: Int?
    /// How many entries the server sent, before those that aren't songs were left out (from a
    /// playlist), so the next page starts after them.
    public let serverCount: Int
    /// Whether every entry the server sent is a song by its type, counting any that couldn't be
    /// read, which `items` leaves out. A playlist's first page tells by this whether the playlist
    /// plays as music.
    public let isAllSongs: Bool

    public init(items: [MusicItem], totalCount: Int?, serverCount: Int? = nil, isAllSongs: Bool = true) {
        self.items = items
        self.totalCount = totalCount
        self.serverCount = serverCount ?? items.count
        self.isAllSongs = isAllSongs
    }
}

/// The rows on a music library's Recommended tab, from Wholphin's `RecommendedMusic`, before
/// its Suggestions row.
public enum MusicRecommendation: CaseIterable, Hashable, Sendable {
    case recentlyReleased
    case recentlyAdded
    case topRated

    public var title: String {
        switch self {
        case .recentlyReleased: String(localized: "Recently Released", bundle: .module)
        case .recentlyAdded: String(localized: "Recently Added", bundle: .module)
        case .topRated: String(localized: "Top Rated", bundle: .module)
        }
    }
}

// MARK: Decoding

extension MusicItem {
    init?(_ dto: BaseItemDto) {
        guard let details = ItemDetails(dto) else { return nil }
        let audio = (dto.mediaSources?.first?.mediaStreams ?? dto.mediaStreams ?? []).filter { $0.type == .audio }
        self.init(
            details: details,
            albumArtist: dto.albumArtist,
            artists: dto.artists ?? [],
            albumArtistLinks: dto.albumArtists.artistLinks,
            artistLinks: dto.artistItems.artistLinks,
            albumName: dto.album,
            albumID: dto.albumID,
            albumImage: ItemImage(itemID: dto.albumID, kind: .primary, tag: dto.albumPrimaryImageTag),
            trackNumber: dto.indexNumber,
            discNumber: dto.parentIndexNumber,
            hasLyrics: dto.hasLyrics ?? false,
            audioStreams: audio.map { AudioStreamInfo(codec: $0.codec, channels: $0.channels) },
            songCount: dto.songCount,
        )
    }
}

private extension [NameIDPair]? {
    var artistLinks: [MusicArtistLink] {
        (self ?? []).compactMap { pair in
            guard let id = pair.id, let name = pair.name else { return nil }
            return MusicArtistLink(id: id, name: name)
        }
    }
}

extension [BaseItemDto]? {
    var musicItems: [MusicItem] {
        (self ?? []).compactMap(MusicItem.init)
    }
}

private extension String {
    var isBlank: Bool {
        allSatisfy(\.isWhitespace)
    }
}

private extension [String?] {
    /// Wholphin's `joinNotBlank`.
    func joinedNotBlank(_ separator: String) -> String? {
        let parts = compactMap(\.self).filter { !$0.isBlank }
        return parts.isEmpty ? nil : parts.joined(separator: separator)
    }
}
