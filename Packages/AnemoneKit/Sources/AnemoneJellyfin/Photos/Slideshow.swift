import Foundation
import JellyfinAPI

/// A photo or a video clip in a slideshow, with what the slideshow's details show about it.
public struct SlideshowItem: Hashable, Identifiable, Sendable {
    public enum Kind: Hashable, Sendable {
        case photo
        /// A clip in a photo album, which plays in place.
        case video
    }

    public let id: MediaItem.ID
    public var name: String
    public var kind: Kind
    /// The photo itself, as the server scales it.
    public var image: ItemImage?
    /// In pixels, when the server knows.
    public var width: Int?
    public var height: Int?
    /// When it was taken, or when the server found it when that isn't known.
    public var date: Date?
    public var overview: String?

    public init(
        id: MediaItem.ID,
        name: String,
        kind: Kind,
        image: ItemImage? = nil,
        width: Int? = nil,
        height: Int? = nil,
        date: Date? = nil,
        overview: String? = nil,
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.image = image
        self.width = width
        self.height = height
        self.date = date
        self.overview = overview
    }
}

/// Which photos a slideshow shows, and in what order: Wholphin's `Destination.Slideshow`, the
/// photos of a library or album as its grid sorts them.
public struct SlideshowQuery: Hashable, Sendable {
    /// The library or album.
    public var folderID: String
    public var sort: LibrarySort
    /// Also the photos in the albums inside it, as Play shows them.
    public var isRecursive: Bool
    /// Wholphin's "Play videos during slideshow": clips play in place, or are left out.
    public var includesVideos: Bool

    public init(
        folderID: String,
        sort: LibrarySort = .default,
        isRecursive: Bool = false,
        includesVideos: Bool = false,
    ) {
        self.folderID = folderID
        self.sort = sort
        self.isRecursive = isRecursive
        self.includesVideos = includesVideos
    }
}

/// One page of a slideshow.
public struct SlideshowPage: Sendable {
    public let items: [SlideshowItem]
    /// How many photos the slideshow holds. Only asked for with the first page.
    public let totalCount: Int?

    public init(items: [SlideshowItem], totalCount: Int?) {
        self.items = items
        self.totalCount = totalCount
    }
}

/// The requests behind a slideshow, ported from Wholphin's `SlideshowViewModel`.
public extension JellyfinSession {
    /// One page of a slideshow, from `startIndex`.
    func slideshowItems(
        _ query: SlideshowQuery,
        startIndex: Int,
        limit: Int,
        includeTotalCount: Bool = false,
    ) async throws -> SlideshowPage {
        var parameters = Paths.GetItemsParameters(userID: userID)
        parameters.parentID = query.folderID
        parameters.includeItemTypes = query.includesVideos ? [.photo, .video] : [.photo]
        parameters.isRecursive = query.isRecursive
        (parameters.sortBy, parameters.sortOrder) = query.sort.slideshowParameters
        parameters.startIndex = startIndex
        parameters.limit = limit
        parameters.enableTotalRecordCount = includeTotalCount
        // Wholphin's `PhotoItemFields`, less what the slideshow doesn't show.
        parameters.fields = [.overview, .width, .height, .dateCreated]
        parameters.enableImageTypes = [.primary]
        parameters.imageTypeLimit = 1
        parameters.enableUserData = false
        let result = try await send(Paths.getItems(parameters: parameters))
        let items = (result.items ?? []).compactMap(SlideshowItem.init)
        return SlideshowPage(items: items, totalCount: includeTotalCount ? result.totalRecordCount ?? items.count : nil)
    }

    /// The IDs of every photo a slideshow shows, and its clips when asked for, for
    /// `ShuffledPages` to shuffle once: IDs only, a thousand at a time, by name so the pages
    /// follow on from each other.
    func slideshowItemIDs(_ query: SlideshowQuery) async throws -> [MediaItem.ID] {
        var parameters = Paths.GetItemsParameters(userID: userID)
        parameters.parentID = query.folderID
        parameters.includeItemTypes = query.includesVideos ? [.photo, .video] : [.photo]
        parameters.isRecursive = query.isRecursive
        parameters.sortBy = [.sortName]
        parameters.sortOrder = [.ascending]
        // Only photos and clips, should the server send anything else.
        return try await itemIDs(parameters) { SlideshowItem($0) != nil }
    }

    /// The slideshow's photos and clips with these IDs, as `slideshowItems` describes them, in
    /// the order given. Any the server no longer has are left out.
    func slideshowItems(ids: [MediaItem.ID]) async throws -> [SlideshowItem] {
        guard !ids.isEmpty else { return [] }
        var parameters = Paths.GetItemsParameters(userID: userID)
        parameters.ids = ids
        parameters.fields = [.overview, .width, .height, .dateCreated]
        parameters.enableImageTypes = [.primary]
        parameters.imageTypeLimit = 1
        parameters.enableUserData = false
        let result = try await send(Paths.getItems(parameters: parameters))
        let found = (result.items ?? []).compactMap(SlideshowItem.init)
        let byID = Dictionary(found.map { ($0.id, $0) }) { first, _ in first }
        return ids.compactMap { byID[$0] }
    }

    /// Fetches a slideshow's pages for `SlideshowPager`: in the order `query` sorts by, or, for
    /// a random sort, one shuffle held for the whole slideshow (see `ShuffledPages`), with
    /// `first` at the start when it's in the slideshow. Shuffle in Wholphin's photo album plays
    /// in order, so the shuffle is Anemone's own.
    func slideshowLoader(for query: SlideshowQuery, first: MediaItem.ID? = nil) -> SlideshowPager.Loader {
        guard query.sort.field == .random else {
            return { [self] startIndex, limit, includeTotalCount in
                try await slideshowItems(
                    query,
                    startIndex: startIndex,
                    limit: limit,
                    includeTotalCount: includeTotalCount,
                )
            }
        }
        let shuffled = ShuffledPages(first: first) { [self] in
            try await slideshowItemIDs(query)
        } items: { [self] ids in
            try await slideshowItems(ids: ids)
        }
        return { startIndex, limit, includeTotalCount in
            let page = try await shuffled.page(startIndex: startIndex, limit: limit)
            return SlideshowPage(items: page.items, totalCount: includeTotalCount ? page.count : nil)
        }
    }

    /// A clip's file, for AVPlayer to play as it is. Wholphin plays slideshow clips this way too,
    /// without a play session.
    func slideshowClipURL(for itemID: MediaItem.ID) -> URL? {
        let parameters = Paths.GetVideoStreamParameters(isStatic: true)
        // AVPlayer can't add the authorization header, so the token goes in the query.
        return client.url(with: Paths.getVideoStream(itemID: itemID, parameters: parameters), queryAPIKey: true)
    }
}

private extension LibrarySort {
    /// The chosen field, then name to break ties; random alone.
    var slideshowParameters: ([ItemSortBy]?, [JellyfinAPI.SortOrder]?) {
        guard field != .default, let sortBy = ItemSortBy(rawValue: field.rawValue) else { return (nil, nil) }
        let order: JellyfinAPI.SortOrder = direction == .ascending ? .ascending : .descending
        guard field != .name, field != .random else { return ([sortBy], [order]) }
        return ([sortBy, .sortName], [order, .ascending])
    }
}

private extension SlideshowItem {
    init?(_ dto: BaseItemDto) {
        guard let id = dto.id else { return nil }
        let kind: Kind
        switch dto.type {
        case .photo: kind = .photo
        case .video: kind = .video
        default: return nil
        }
        self.init(
            id: id,
            name: dto.name ?? "",
            kind: kind,
            image: ItemImage(itemID: id, kind: .primary, tag: dto.imageTags?[ImageType.primary.rawValue]),
            width: dto.width,
            height: dto.height,
            date: dto.premiereDate ?? dto.dateCreated,
            overview: dto.overview,
        )
    }
}
