import Foundation
import Observation

/// A library's items, fetched a page at a time as the grid reaches them, like Wholphin's
/// `ApiRequestPager`. Loaded pages are kept, so scrolling back never shows placeholders again;
/// even a 20,000-item library is only a few megabytes. A page that comes back short closes up
/// (`PagedItems`), so no card waits for an item that will never come.
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
    /// How many items the grid holds: those the first page counted, less any that pages loaded
    /// since left out. Kept apart from the items, so the grid redraws only when it changes.
    public private(set) var count = 0
    /// The most recent failure to load a page; cleared when a page loads.
    public private(set) var error: (any Error)?
    private var items: PagedItems<LibraryEntry>
    @ObservationIgnored private var loads: [Int: Task<[LibraryEntry], any Error>] = [:]
    @ObservationIgnored private let loader: Loader

    public init(pageSize: Int = defaultPageSize, loader: @escaping Loader) {
        self.pageSize = pageSize
        self.loader = loader
        items = PagedItems(pageSize: pageSize)
    }

    /// Loads the first page and the total count. Call once, before showing the grid.
    public func start() async throws {
        let first = try await loader(0, pageSize, true)
        items.start(first.items, counted: first.totalCount ?? first.items.count)
        count = items.count
    }

    /// The item at `index`, or `nil` while its page is loading.
    public func item(at index: Int) -> LibraryEntry? {
        items.item(at: index)
    }

    /// Called as cards come on screen: loads the page holding `index`, and the next one once
    /// `index` is past the middle of its page, so it's there before focus gets to it.
    public func prefetch(around index: Int) async {
        _ = try? await load(at: index)
        if let page = items.page(holding: index), index - items.index(of: 0, onPage: page) >= pageSize / 2 {
            _ = try? await load(page: page + 1)
        }
    }

    /// The item at `index`, loading its page first if needed; for jumps and random picks.
    public func load(at index: Int) async throws -> LibraryEntry? {
        // A page that comes back short moves the items after it up, which can put `index` on a
        // page not loaded yet; each turn loads one more page, so this ends.
        while let page = items.page(holding: index), items.items(onPage: page) == nil {
            try await load(page: page)
        }
        return item(at: index)
    }

    /// Takes items deleted from the app out of the grid, which closes up around them as the
    /// server's list has, without loading again: the pages still to come are asked for from where
    /// that list now has them. Episodes of a deleted series go with it.
    public func remove(_ deleted: Set<MediaItem.ID>) {
        guard items.remove(where: { $0.item.wasDeleted(in: deleted) }) > 0 else { return }
        count = items.count
    }

    /// Fetches a page unless it's loaded or on its way. Callers wait without owning the request,
    /// so a card scrolling away doesn't cancel a page other cards need.
    @discardableResult
    private func load(page: Int) async throws -> [LibraryEntry] {
        if let loaded = items.items(onPage: page) {
            return loaded
        }
        guard items.hasPage(page) else { return [] }
        let startIndex = items.startIndex(ofPage: page)
        let task = loads[page] ?? Task { [loader, pageSize] in
            try await loader(startIndex, pageSize, false).items
        }
        loads[page] = task
        do {
            let loaded = try await task.value
            items.set(loaded, onPage: page)
            if count != items.count {
                count = items.count
            }
            loads[page] = nil
            error = nil
            return loaded
        } catch {
            // Dropped so the next card to ask tries again.
            loads[page] = nil
            self.error = error
            throw error
        }
    }
}
