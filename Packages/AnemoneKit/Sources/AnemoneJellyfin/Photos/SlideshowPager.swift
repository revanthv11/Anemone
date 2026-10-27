import Foundation
import Observation

/// A slideshow's photos, fetched a page at a time as the slideshow reaches them, like Wholphin's
/// `ApiRequestPager`. Loaded pages are kept, so going back never waits.
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
    /// How many photos the slideshow holds, as the first page reported it.
    public private(set) var count = 0
    private var pages: [Int: [SlideshowItem]] = [:]
    @ObservationIgnored private var loads: [Int: Task<[SlideshowItem], any Error>] = [:]
    @ObservationIgnored private let loader: Loader

    public init(pageSize: Int = 100, loader: @escaping Loader) {
        self.pageSize = pageSize
        self.loader = loader
    }

    /// Loads the first page and the total count. Call once, before showing anything.
    public func start() async throws {
        let first = try await loader(0, pageSize, true)
        pages[0] = first.items
        count = first.totalCount ?? first.items.count
    }

    /// The photo at `index`, or `nil` while its page is loading.
    public func item(at index: Int) -> SlideshowItem? {
        let page = index / pageSize
        guard index >= 0, let items = pages[page] else { return nil }
        let offset = index - page * pageSize
        return items.indices.contains(offset) ? items[offset] : nil
    }

    /// The photo at `index`, loading its page first if needed.
    public func load(at index: Int) async throws -> SlideshowItem? {
        try await load(page: index / pageSize)
        return item(at: index)
    }

    /// Where the photo with `id` is, looking first at the page holding `hint`, then at the pages
    /// before it, then after. A photo picked in an album's grid is at or before its place there,
    /// since the slideshow leaves out the albums and clips the grid shows.
    public func index(of id: MediaItem.ID, near hint: Int) async throws -> Int? {
        guard count > 0 else { return nil }
        let lastPage = (count - 1) / pageSize
        let hintPage = min(max(hint, 0) / pageSize, lastPage)
        let order = Array(stride(from: hintPage, through: 0, by: -1)) + Array((hintPage + 1) ..< (lastPage + 1))
        for page in order {
            let items = try await load(page: page)
            if let offset = items.firstIndex(where: { $0.id == id }) {
                return page * pageSize + offset
            }
        }
        return nil
    }

    /// Fetches a page unless it's loaded or on its way.
    @discardableResult
    private func load(page: Int) async throws -> [SlideshowItem] {
        if let items = pages[page] {
            return items
        }
        guard page >= 0, page * pageSize < count else { return [] }
        let task = loads[page] ?? Task { [loader, pageSize] in
            try await loader(page * pageSize, pageSize, false).items
        }
        loads[page] = task
        do {
            let items = try await task.value
            pages[page] = items
            loads[page] = nil
            return items
        } catch {
            // Dropped so the next ask tries again.
            loads[page] = nil
            throw error
        }
    }
}
