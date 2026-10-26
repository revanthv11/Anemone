import Foundation
import Observation

/// A library's items, fetched a page at a time as the grid reaches them, like Wholphin's
/// `ApiRequestPager`. Loaded pages are kept, so scrolling back never shows placeholders again;
/// even a 20,000-item library is only a few megabytes.
@MainActor
@Observable
public final class LibraryPager {
    /// Fetches `limit` items from `startIndex`, with the total count when asked for it.
    public typealias Loader = @Sendable (
        _ startIndex: Int,
        _ limit: Int,
        _ includeTotalCount: Bool,
    ) async throws -> LibraryPage

    /// Wholphin's page size.
    public static let defaultPageSize = 100

    public let pageSize: Int
    /// How many items the library holds, as the first page reported it.
    public private(set) var count = 0
    /// The most recent failure to load a page; cleared when a page loads.
    public private(set) var error: (any Error)?
    private var pages: [Int: [LibraryEntry]] = [:]
    @ObservationIgnored private var loads: [Int: Task<[LibraryEntry], any Error>] = [:]
    @ObservationIgnored private let loader: Loader

    public init(pageSize: Int = defaultPageSize, loader: @escaping Loader) {
        self.pageSize = pageSize
        self.loader = loader
    }

    /// Loads the first page and the total count. Call once, before showing the grid.
    public func start() async throws {
        let first = try await loader(0, pageSize, true)
        pages[0] = first.items
        count = first.totalCount ?? first.items.count
    }

    /// The item at `index`, or `nil` while its page is loading.
    public func item(at index: Int) -> LibraryEntry? {
        let page = index / pageSize
        guard let items = pages[page] else { return nil }
        let offset = index - page * pageSize
        return items.indices.contains(offset) ? items[offset] : nil
    }

    /// Called as cards come on screen: loads the page holding `index`, and the next one once
    /// `index` is past the middle of its page, so it's there before focus gets to it.
    public func prefetch(around index: Int) async {
        let page = index / pageSize
        var wanted = [page]
        if index % pageSize >= pageSize / 2 {
            wanted.append(page + 1)
        }
        for page in wanted {
            _ = try? await load(page: page)
        }
    }

    /// The item at `index`, loading its page first if needed; for jumps and random picks.
    public func load(at index: Int) async throws -> LibraryEntry? {
        try await load(page: index / pageSize)
        return item(at: index)
    }

    /// Fetches a page unless it's loaded or on its way. Callers wait without owning the request,
    /// so a card scrolling away doesn't cancel a page other cards need.
    @discardableResult
    private func load(page: Int) async throws -> [LibraryEntry] {
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
            error = nil
            return items
        } catch {
            // Dropped so the next card to ask tries again.
            loads[page] = nil
            self.error = error
            throw error
        }
    }
}
