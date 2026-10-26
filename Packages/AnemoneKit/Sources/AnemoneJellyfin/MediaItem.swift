import Foundation
import JellyfinAPI

/// A movie, episode, series or other item, with what cards, headers and detail pages show.
public struct MediaItem: Hashable, Identifiable, Sendable {
    public enum Kind: Hashable, Sendable {
        case movie
        case series
        case season
        case episode
        case collection
        case playlist
        case person
        case video
        case musicVideo
        case musicAlbum
        case audio
        case photo
        case folder
        case other
    }

    /// Where an episode sits in its series.
    public struct Episode: Hashable, Sendable {
        public let seriesID: String?
        public let seriesName: String?
        public let seasonNumber: Int?
        public let episodeNumber: Int?

        public init(seriesID: String?, seriesName: String?, seasonNumber: Int? = nil, episodeNumber: Int? = nil) {
            self.seriesID = seriesID
            self.seriesName = seriesName
            self.seasonNumber = seasonNumber
            self.episodeNumber = episodeNumber
        }
    }

    /// The image tags the server sent. A tag changes whenever its image does, so URLs built from
    /// tags can be cached for good.
    public struct Artwork: Hashable, Sendable {
        public var primaryTag: String?
        public var thumbTag: String?
        /// The first backdrop.
        public var backdropTag: String?
        /// For episodes and seasons, the series' poster.
        public var seriesPrimary: ItemImage?
        /// The nearest parent with a thumb; for episodes, usually the series.
        public var parentThumb: ItemImage?
        /// The nearest parent with a backdrop; for episodes, usually the series.
        public var parentBackdrop: ItemImage?

        public init(
            primaryTag: String? = nil,
            thumbTag: String? = nil,
            backdropTag: String? = nil,
            seriesPrimary: ItemImage? = nil,
            parentThumb: ItemImage? = nil,
            parentBackdrop: ItemImage? = nil,
        ) {
            self.primaryTag = primaryTag
            self.thumbTag = thumbTag
            self.backdropTag = backdropTag
            self.seriesPrimary = seriesPrimary
            self.parentThumb = parentThumb
            self.parentBackdrop = parentBackdrop
        }
    }

    public let id: String
    public var name: String
    public var kind: Kind
    /// Set for episodes and seasons.
    public var episode: Episode?
    public var year: Int?
    public var overview: String?
    public var runtime: Duration?
    /// The age rating, such as "PG-13".
    public var officialRating: String?
    /// How much has been watched, from 0 to 1. `nil` when nothing has.
    public var progress: Double?
    public var artwork: Artwork

    public init(
        id: String,
        name: String,
        kind: Kind,
        episode: Episode? = nil,
        year: Int? = nil,
        overview: String? = nil,
        runtime: Duration? = nil,
        officialRating: String? = nil,
        progress: Double? = nil,
        artwork: Artwork = Artwork(),
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.episode = episode
        self.year = year
        self.overview = overview
        self.runtime = runtime
        self.officialRating = officialRating
        self.progress = progress
        self.artwork = artwork
    }

    /// The series name for episodes and seasons, otherwise the item's own name, like
    /// Wholphin's home header.
    public var displayTitle: String {
        switch kind {
        case .episode, .season:
            episode?.seriesName ?? name
        default:
            name
        }
    }

    /// "S1:E3" for an episode whose numbers are known.
    public var episodeLabel: String? {
        guard kind == .episode, let season = episode?.seasonNumber, let number = episode?.episodeNumber else {
            return nil
        }
        return "S\(season):E\(number)"
    }

    /// The series this episode or season belongs to, standing in for it. Uses only what the
    /// episode carries, so there's no overview or year.
    public var seriesStandIn: MediaItem? {
        guard kind == .episode || kind == .season, let seriesID = episode?.seriesID else { return nil }
        return MediaItem(
            id: seriesID,
            name: episode?.seriesName ?? name,
            kind: .series,
            artwork: Artwork(
                primaryTag: artwork.seriesPrimary?.tag,
                thumbTag: artwork.parentThumb.flatMap { $0.itemID == seriesID ? $0.tag : nil },
                backdropTag: artwork.parentBackdrop.flatMap { $0.itemID == seriesID ? $0.tag : nil },
            ),
        )
    }

    /// Replaces episodes and seasons with their series, keeping the first appearance of each
    /// item. The server groups several new episodes of one series itself, but sends a lone new
    /// episode as is.
    public static func groupedBySeries(_ items: [MediaItem]) -> [MediaItem] {
        var seen = Set<String>()
        return items.compactMap { item in
            let shown = item.seriesStandIn ?? item
            return seen.insert(shown.id).inserted ? shown : nil
        }
    }
}

extension MediaItem {
    init?(_ dto: BaseItemDto) {
        guard let id = dto.id else { return nil }
        let kind = Kind(dto.type)
        let episode: Episode? = switch kind {
        case .episode:
            Episode(
                seriesID: dto.seriesID,
                seriesName: dto.seriesName,
                seasonNumber: dto.parentIndexNumber,
                episodeNumber: dto.indexNumber,
            )
        case .season:
            Episode(seriesID: dto.seriesID, seriesName: dto.seriesName, seasonNumber: dto.indexNumber)
        default:
            nil
        }
        self.init(
            id: id,
            name: dto.name ?? "",
            kind: kind,
            episode: episode,
            year: dto.productionYear,
            overview: dto.overview,
            runtime: dto.runTimeTicks.map(Duration.init(ticks:)),
            officialRating: dto.officialRating,
            progress: dto.userData?.playedPercentage.flatMap { $0 > 0 ? min($0 / 100, 1) : nil },
            artwork: Artwork(
                primaryTag: dto.imageTags?[ImageType.primary.rawValue],
                thumbTag: dto.imageTags?[ImageType.thumb.rawValue],
                backdropTag: dto.backdropImageTags?.first,
                seriesPrimary: ItemImage(itemID: dto.seriesID, kind: .primary, tag: dto.seriesPrimaryImageTag),
                parentThumb: ItemImage(itemID: dto.parentThumbItemID, kind: .thumb, tag: dto.parentThumbImageTag),
                parentBackdrop: ItemImage(
                    itemID: dto.parentBackdropItemID,
                    kind: .backdrop,
                    tag: dto.parentBackdropImageTags?.first,
                ),
            ),
        )
    }
}

private extension MediaItem.Kind {
    init(_ kind: BaseItemKind?) {
        self = kind.flatMap { Self.byItemKind[$0] } ?? .other
    }

    static let byItemKind: [BaseItemKind: Self] = [
        .movie: .movie,
        .series: .series,
        .season: .season,
        .episode: .episode,
        .boxSet: .collection,
        .playlist: .playlist,
        .person: .person,
        .video: .video,
        .musicVideo: .musicVideo,
        .musicAlbum: .musicAlbum,
        .audio: .audio,
        .photo: .photo,
        .folder: .folder,
        .collectionFolder: .folder,
        .photoAlbum: .folder,
    ]
}
