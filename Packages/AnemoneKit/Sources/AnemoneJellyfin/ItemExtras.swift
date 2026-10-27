import Foundation
import Get
import JellyfinAPI

/// What an item page shows beyond `ItemDetails`: the item's chapters, trailers and special
/// features, and whether the user may delete it. Empty until loaded, and for items without any.
public struct ItemExtras: Hashable, Sendable {
    /// The item these are for; `nil` before anything has loaded.
    public var itemID: MediaItem.ID?
    /// In order of where they start.
    public var chapters: [Chapter]
    /// Local trailers first, then remote ones, official trailers before teasers.
    public var trailers: [Trailer]
    /// Special features such as featurettes, one entry per kind.
    public var features: [ExtrasEntry]
    /// Whether the server lets this user delete the item, its `CanDelete`.
    public var canDelete: Bool

    public init(
        itemID: MediaItem.ID? = nil,
        chapters: [Chapter] = [],
        trailers: [Trailer] = [],
        features: [ExtrasEntry] = [],
        canDelete: Bool = false,
    ) {
        self.itemID = itemID
        self.chapters = chapters
        self.trailers = trailers
        self.features = features
        self.canDelete = canDelete
    }
}

/// A chapter marker in a movie or episode, ported from Wholphin's `Chapter`.
public struct Chapter: Hashable, Identifiable, Sendable {
    public let itemID: MediaItem.ID
    /// Where the server lists it among the item's chapters, counting from 0. Chapter images are
    /// asked for by this.
    public let index: Int
    public let name: String?
    public let start: Duration
    /// The chapter image's tag; `nil` when the server has no image for it.
    public let imageTag: String?

    public init(itemID: MediaItem.ID, index: Int, name: String?, start: Duration, imageTag: String? = nil) {
        self.itemID = itemID
        self.index = index
        self.name = name
        self.start = start
        self.imageTag = imageTag
    }

    public var id: String {
        "\(index)"
    }
}

/// A trailer: a video in the library, or a page elsewhere such as YouTube. Ported from
/// Wholphin's `Trailer`, `LocalTrailer` and `RemoteTrailer`.
public struct Trailer: Hashable, Identifiable, Sendable {
    public enum Source: Hashable, Sendable {
        /// A trailer file stored with the item, which plays like any video.
        case local(ItemDetails)
        /// A web page, which tvOS can only open in an app that handles it.
        case remote(URL)
    }

    public let name: String
    public let source: Source

    public init(name: String, source: Source) {
        self.name = name
        self.source = source
    }

    public var id: String {
        switch source {
        case let .local(details): details.id
        case let .remote(url): url.absoluteString
        }
    }

    /// Where it comes from, as Wholphin's trailer list says it: "Local", "YouTube" or "External".
    public var sourceName: String {
        switch source {
        case .local: "Local"
        case .remote: youTubeAppURL == nil ? "External" : "YouTube"
        }
    }

    /// For a YouTube trailer, the link that opens it in the YouTube app, adapted from Swiftfin's
    /// `ExternalTrailerURL`: the web address behind the app's own scheme.
    public var youTubeAppURL: URL? {
        guard case let .remote(url) = source, let host = url.host()?.lowercased(),
              Self.youTubeHosts.contains(host)
        else { return nil }
        return URL(string: "youtube://\(url.absoluteString)")
    }

    private static let youTubeHosts: Set = ["youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be"]
}

/// The kinds of special feature, in the order Wholphin shows them (`ExtraType.sortOrder`).
public enum ExtraKind: Hashable, CaseIterable, Sendable {
    case trailer
    case featurette
    case short
    case clip
    case scene
    case sample
    case deletedScene
    case interview
    case behindTheScenes
    case themeSong
    case themeVideo
    case other

    /// Wholphin's name for several, such as "Featurettes".
    public var title: String {
        switch self {
        case .trailer: "Trailers"
        case .featurette: "Featurettes"
        case .short: "Shorts"
        case .clip: "Clips"
        case .scene: "Scenes"
        case .sample: "Samples"
        case .deletedScene: "Deleted Scenes"
        case .interview: "Interviews"
        case .behindTheScenes: "Behind the Scenes"
        case .themeSong: "Theme Songs"
        case .themeVideo: "Theme Videos"
        case .other: "Other"
        }
    }

    /// Wholphin's name for one, such as "Featurette".
    public var singularTitle: String {
        switch self {
        case .trailer: "Trailer"
        case .featurette: "Featurette"
        case .short: "Short"
        case .clip: "Clip"
        case .scene: "Scene"
        case .sample: "Sample"
        case .deletedScene: "Deleted scene"
        case .interview: "Interview"
        case .behindTheScenes: "Behind the scenes"
        case .themeSong: "Theme song"
        case .themeVideo: "Theme video"
        case .other: "Other"
        }
    }
}

/// One card in an item's Extras row, ported from Wholphin's `ExtrasItem`: a single extra, or every
/// extra of one kind when there are several.
public struct ExtrasEntry: Hashable, Identifiable, Sendable {
    public let kind: ExtraKind
    /// Never empty.
    public let items: [ItemDetails]

    public init(kind: ExtraKind, items: [ItemDetails]) {
        self.kind = kind
        self.items = items
    }

    /// Each kind has one entry.
    public var id: String {
        "\(kind)"
    }

    /// A single extra's own name, or the kind's when it has none; several go by their kind.
    public var title: String {
        if items.count == 1, let name = items.first?.item.name, !name.isEmpty {
            return name
        }
        return items.count == 1 ? kind.singularTitle : kind.title
    }

    /// The kind under a single extra's own name, or how many extras a group holds.
    public var subtitle: String? {
        if items.count > 1 {
            return "\(items.count) items"
        }
        return title == kind.singularTitle ? nil : kind.singularTitle
    }

    /// Whether every extra in it has been watched.
    public var isPlayed: Bool {
        items.allSatisfy(\.userState.isPlayed)
    }

    /// A single extra's progress; groups show none, as in Wholphin.
    public var progress: Double? {
        items.count == 1 ? items.first?.item.progress : nil
    }

    /// Groups the server's special features into entries, as Wholphin's `ExtrasService` does:
    /// trailers and theme music are left out, since the page has its own ways to them.
    static func entries(_ features: [BaseItemDto]) -> [Self] {
        let shown = features.compactMap { dto -> (ExtraKind, ItemDetails)? in
            let kind = ExtraKind(dto.extraType)
            guard ![.trailer, .themeSong, .themeVideo].contains(kind),
                  let details = ItemDetails(dto) else { return nil }
            return (kind, details)
        }
        let byKind = Dictionary(grouping: shown) { $0.0 }
        return ExtraKind.allCases.compactMap { kind in
            byKind[kind].map { Self(kind: kind, items: $0.map(\.1)) }
        }
    }
}

/// Requests for item page extras, ported from Wholphin's `TrailerService`, `ExtrasService` and
/// `MediaManagementService`.
public extension JellyfinSession {
    /// An item's chapters, trailers, special features, and whether the user may delete it.
    /// `/Items/{id}` sends the chapters, remote trailers and `CanDelete`, and counts the rest:
    /// local trailers and special features each take a request of their own, made only when the
    /// item has some. As in Wholphin, the page goes without those when their request fails.
    func itemExtras(id: MediaItem.ID) async throws -> ItemExtras {
        let dto = try await send(Paths.getItem(itemID: id, userID: userID))
        async let local = (dto.localTrailerCount ?? 0) > 0
            ? optionalExtra { try await send(Paths.getLocalTrailers(itemID: id, userID: userID)) }
            : []
        // Asked for unless the server says there are none.
        async let features = dto.specialFeatureCount == 0
            ? []
            : optionalExtra { try await send(Paths.getSpecialFeatures(itemID: id, userID: userID)) }
        let localTrailers = try await local.compactMap { trailer in
            ItemDetails(trailer).map { Trailer(name: $0.item.name, source: .local($0)) }
        }
        return try await ItemExtras(
            itemID: id,
            chapters: Chapter.chapters(of: dto),
            trailers: localTrailers + Trailer.remote(dto.remoteTrailers ?? []),
            features: ExtrasEntry.entries(features),
            canDelete: dto.canDelete ?? false,
        )
    }

    /// Deletes an item from the library and from the server's disk. The server refuses unless
    /// the item's `canDelete` is set for the user.
    func deleteItem(id: MediaItem.ID) async throws {
        try await send(Paths.deleteItem(itemID: id))
    }

    /// A chapter's image, scaled down to `maxWidth` pixels. `nil` when it has none.
    func imageURL(for chapter: Chapter, maxWidth: Int) -> URL? {
        guard let tag = chapter.imageTag else { return nil }
        let parameters = Paths.GetItemImageByIndexParameters(maxWidth: maxWidth, quality: 96, tag: tag)
        let request = Paths.getItemImageByIndex(
            itemID: chapter.itemID,
            imageType: ImageType.chapter.rawValue,
            imageIndex: chapter.index,
            parameters: parameters,
        )
        return JellyfinURLs.url(for: request, on: serverURL)
    }

    /// A collection's items, ordered and narrowed as its page's sort and filter options say, like
    /// Wholphin's `CollectionViewModel`. The default order is the collection's own.
    func collectionItems(
        id: MediaItem.ID,
        sort: LibrarySort,
        filter: LibraryFilter,
    ) async throws -> [ItemDetails] {
        let collection = Library(id: id, name: "", kind: .collections)
        var parameters = LibraryQuery(library: collection, sort: sort, filter: filter).itemsParameters(userID: userID)
        if sort.field == .default {
            parameters.sortBy = [.default]
            parameters.sortOrder = [sort.direction == .ascending ? JellyfinAPI.SortOrder.ascending : .descending]
        }
        parameters.fields = [.overview, .primaryImageAspectRatio, .childCount]
        parameters.enableUserData = true
        return try await (send(Paths.getItems(parameters: parameters)).items ?? []).compactMap(ItemDetails.init)
    }
}

extension Chapter {
    /// In order of where they start, keeping the server's index for their images.
    static func chapters(of dto: BaseItemDto) -> [Chapter] {
        guard let itemID = dto.id else { return [] }
        return (dto.chapters ?? []).enumerated()
            .map { index, chapter in
                Chapter(
                    itemID: itemID,
                    index: index,
                    name: chapter.name.flatMap { $0.isEmpty ? nil : $0 },
                    start: Duration(ticks: chapter.startPositionTicks ?? 0),
                    imageTag: chapter.imageTag,
                )
            }
            .sorted { ($0.start, $0.index) < ($1.start, $1.index) }
    }
}

extension Trailer {
    /// The server's remote trailers, ordered as Wholphin orders them: official trailers first,
    /// then other trailers, then anything else, then teasers, each by name.
    static func remote(_ links: [NamedURL]) -> [Trailer] {
        links.compactMap { link in
            guard let url = link.url.flatMap(URL.init(string:)) else { return nil }
            let name = link.name.flatMap { $0.isEmpty ? nil : $0 } ?? "Trailer"
            return Trailer(name: name, source: .remote(url))
        }
        .sorted { ($0.rank, $0.name) < ($1.rank, $1.name) }
    }

    private var rank: Int {
        let name = name.lowercased()
        return if name.contains("official trailer") || name.contains("official theatrical trailer") {
            0
        } else if name.contains("teaser") {
            10
        } else if name.contains("trailer") {
            1
        } else {
            5
        }
    }
}

private extension ExtraKind {
    init(_ type: ExtraType?) {
        self = type.flatMap { Self.byExtraType[$0] } ?? .other
    }

    static let byExtraType: [ExtraType: Self] = [
        .trailer: .trailer,
        .featurette: .featurette,
        .short: .short,
        .clip: .clip,
        .scene: .scene,
        .sample: .sample,
        .deletedScene: .deletedScene,
        .interview: .interview,
        .behindTheScenes: .behindTheScenes,
        .themeSong: .themeSong,
        .themeVideo: .themeVideo,
    ]
}

private extension JellyfinSession {
    /// A request for part of the extras that the page can do without: its failure leaves it out,
    /// though a revoked token still counts as signed out.
    func optionalExtra(_ request: () async throws -> [BaseItemDto]) async throws -> [BaseItemDto] {
        do {
            return try await request()
        } catch SessionError.signedOut {
            throw SessionError.signedOut
        } catch {
            return []
        }
    }
}
