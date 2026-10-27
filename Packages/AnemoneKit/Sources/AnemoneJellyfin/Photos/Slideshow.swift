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
