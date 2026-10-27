import AnemoneJellyfin
import Observation

/// A music list fetched a page at a time as the grid reaches it, like `LibraryPager` (Wholphin's
/// `ApiRequestPager`), for music items with their artists.
@MainActor
@Observable
final class MusicPager {
    typealias Loader = @Sendable (_ startIndex: Int, _ limit: Int, _ includeTotalCount: Bool) async throws -> MusicPage

    static let pageSize = 100

    private(set) var count = 0
    /// The most recent failure to load a page; cleared when a page loads.
    private(set) var error: (any Error)?
    private var pages: [Int: [MusicItem]] = [:]
    @ObservationIgnored private var loads: [Int: Task<[MusicItem], any Error>] = [:]
    @ObservationIgnored private let loader: Loader

    init(loader: @escaping Loader) {
        self.loader = loader
    }

    /// Loads the first page and the total count. Call once, before showing the grid.
    func start() async throws {
        let first = try await loader(0, Self.pageSize, true)
        pages[0] = first.items
        count = first.totalCount ?? first.items.count
    }

    /// The item at `index`, or `nil` while its page is loading.
    func item(at index: Int) -> MusicItem? {
        let page = index / Self.pageSize
        let offset = index - page * Self.pageSize
        guard let items = pages[page], items.indices.contains(offset) else { return nil }
        return items[offset]
    }

    /// Loads the page holding `index`, and the next one past the middle of a page.
    func prefetch(around index: Int) async {
        var wanted = [index / Self.pageSize]
        if index % Self.pageSize >= Self.pageSize / 2 {
            wanted.append(index / Self.pageSize + 1)
        }
        for page in wanted {
            _ = try? await load(page: page)
        }
    }

    @discardableResult
    private func load(page: Int) async throws -> [MusicItem] {
        if let items = pages[page] {
            return items
        }
        guard page >= 0, page * Self.pageSize < count else { return [] }
        let task = loads[page] ?? Task { [loader] in
            try await loader(page * Self.pageSize, Self.pageSize, false).items
        }
        loads[page] = task
        do {
            let items = try await task.value
            pages[page] = items
            loads[page] = nil
            error = nil
            return items
        } catch {
            loads[page] = nil
            self.error = error
            throw error
        }
    }
}
