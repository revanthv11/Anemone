import Foundation
import Observation

/// A slideshow's photos, fetched a page at a time as the slideshow reaches them, like Wholphin's
/// `ApiRequestPager`. Loaded pages are kept, so going back never waits. A page that comes back
/// short closes up (`PagedItems`), so the slideshow never stops on a photo that will never come.
@MainActor
@Observable
public final class SlideshowPager {
    /// Fetches `limit` photos from `startIndex`, with the total count when asked for it.
    public typealias Loader = @Sendable (
        _ startIndex: Int,
        _ limit: Int,
        _ includeTotalCount: Bool,
    ) async throws -> SlideshowPage

    public let pageSize: Int
    /// How many photos the slideshow holds: those the first page counted, less any that pages
    /// loaded since left out.
    public private(set) var count = 0
    private var items: PagedItems<SlideshowItem>
    @ObservationIgnored private var loads: [Int: Task<[SlideshowItem], any Error>] = [:]
    @ObservationIgnored private let loader: Loader

    public init(pageSize: Int = 100, loader: @escaping Loader) {
        self.pageSize = pageSize
        self.loader = loader
        items = PagedItems(pageSize: pageSize)
    }

    /// Loads the first page and the total count. Call once, before showing anything.
    public func start() async throws {
        let first = try await loader(0, pageSize, true)
        items.start(first.items, counted: first.totalCount ?? first.items.count)
        count = items.count
    }

    /// The photo at `index`, or `nil` while its page is loading.
    public func item(at index: Int) -> SlideshowItem? {
        items.item(at: index)
    }

    /// The photo at `index`, loading its page first if needed.
    public func load(at index: Int) async throws -> SlideshowItem? {
        // A page that comes back short moves the photos after it up, which can put `index` on a
        // page not loaded yet; each turn loads one more page, so this ends.
        while let page = items.page(holding: index), items.items(onPage: page) == nil {
            try await load(page: page)
        }
        return item(at: index)
    }

    /// Where the photo with `id` is, looking first at the page holding `hint`, then at the pages
    /// before it, then after. A photo picked in an album's grid is at or before its place there,
    /// since the slideshow leaves out the albums and clips the grid shows.
    public func index(of id: MediaItem.ID, near hint: Int) async throws -> Int? {
        guard count > 0 else { return nil }
        let lastPage = items.pageCount - 1
        let hintPage = min(max(hint, 0) / pageSize, lastPage)
        let order = Array(stride(from: hintPage, through: 0, by: -1)) + Array((hintPage + 1) ..< (lastPage + 1))
        for page in order {
            let loaded = try await load(page: page)
            if let offset = loaded.firstIndex(where: { $0.id == id }) {
                return items.index(of: offset, onPage: page)
            }
        }
        return nil
    }

    /// Fetches a page unless it's loaded or on its way.
    @discardableResult
    private func load(page: Int) async throws -> [SlideshowItem] {
        if let loaded = items.items(onPage: page) {
            return loaded
        }
        guard items.hasPage(page) else { return [] }
        let task = loads[page] ?? Task { [loader, pageSize] in
            try await loader(page * pageSize, pageSize, false).items
        }
        loads[page] = task
        do {
            let loaded = try await task.value
            items.set(loaded, onPage: page)
            if count != items.count {
                count = items.count
            }
            loads[page] = nil
            return loaded
        } catch {
            // Dropped so the next ask tries again.
            loads[page] = nil
            throw error
        }
    }
}
