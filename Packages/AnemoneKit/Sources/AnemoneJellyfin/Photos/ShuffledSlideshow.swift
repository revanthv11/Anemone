import Foundation

/// A slideshow in a random order that holds for the whole slideshow. The server's random sort
/// draws a new order for every request, so a slideshow fetched a page at a time with it shows
/// some photos twice and others never once it has more than a page, and a photo picked in a
/// grid sorted at random may not be found in it. Instead the IDs are fetched once and shuffled
/// here, and each page's photos are fetched by ID. Shuffle in Wholphin's photo album plays in
/// order, so this is Anemone's own.
public actor ShuffledSlideshow {
    public typealias IDs = @Sendable () async throws -> [MediaItem.ID]
    public typealias Items = @Sendable ([MediaItem.ID]) async throws -> [SlideshowItem]

    private let first: MediaItem.ID?
    private let ids: IDs
    private let items: Items
    private var order: Task<[MediaItem.ID], any Error>?

    /// - Parameters:
    ///   - first: the photo picked to open the slideshow on, put first when it's there.
    ///   - ids: every photo's ID, in any order.
    ///   - items: the photos with the IDs given, in that order.
    public init(first: MediaItem.ID?, ids: @escaping IDs, items: @escaping Items) {
        self.first = first
        self.ids = ids
        self.items = items
    }

    /// `limit` photos from `startIndex` in the shuffled order, for `SlideshowPager`.
    public func page(startIndex: Int, limit: Int, includeTotalCount: Bool) async throws -> SlideshowPage {
        let order = try await shuffled()
        let pageIDs = Array(order.dropFirst(startIndex).prefix(limit))
        return try await SlideshowPage(items: items(pageIDs), totalCount: includeTotalCount ? order.count : nil)
    }

    /// The IDs, shuffled once; asked for again if fetching them failed.
    private func shuffled() async throws -> [MediaItem.ID] {
        let task = order ?? Task { [ids, first] in
            var order = try await ids().shuffled()
            if let first, let index = order.firstIndex(of: first) {
                order.swapAt(0, index)
            }
            return order
        }
        order = task
        do {
            return try await task.value
        } catch {
            if order == task {
                order = nil
            }
            throw error
        }
    }
}
