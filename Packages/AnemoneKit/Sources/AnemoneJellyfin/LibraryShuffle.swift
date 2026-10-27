import Foundation
import JellyfinAPI

/// A list in a random order that holds for as long as the list is open, fetched a page at a
/// time: a library grid sorted at random, or a shuffled slideshow. The server's random sort
/// draws a new order for every request (and some servers answer it in name order), so a list
/// paged with it shows some items twice and others never once it has more than a page. Instead
/// the IDs are fetched once and shuffled here, and each page's items are fetched by ID.
public actor ShuffledPages<Item: Sendable> {
    public typealias IDs = @Sendable () async throws -> [MediaItem.ID]
    public typealias Items = @Sendable ([MediaItem.ID]) async throws -> [Item]

    private let first: MediaItem.ID?
    private let ids: IDs
    private let items: Items
    private var order: Task<[MediaItem.ID], any Error>?

    /// - Parameters:
    ///   - first: the item to put first when it's there, such as the photo picked to open a
    ///     slideshow on.
    ///   - ids: every item's ID, in any order.
    ///   - items: the items with the IDs given, in that order.
    public init(first: MediaItem.ID? = nil, ids: @escaping IDs, items: @escaping Items) {
        self.first = first
        self.ids = ids
        self.items = items
    }

    /// `limit` items from `startIndex` in the shuffled order, and how many there are in all.
    public func page(startIndex: Int, limit: Int) async throws -> (items: [Item], count: Int) {
        let order = try await shuffled()
        let pageIDs = Array(order.dropFirst(startIndex).prefix(limit))
        return try await (items(pageIDs), order.count)
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

public extension JellyfinSession {
    /// Fetches a library grid's pages for `LibraryPager`: in the order `query` sorts by, or, for
    /// a random sort, in one order drawn when the grid loads and held while it's open (see
    /// `ShuffledPages`). Wholphin sends the server's random sort with every page, so its random
    /// grids repeat and miss titles past the first page; the IDs here come from the same request
    /// Wholphin pages through, by name.
    func libraryLoader(for query: LibraryQuery) -> LibraryPager.Loader {
        guard query.sort.field == .random else {
            return { [self] startIndex, limit, includeTotalCount in
                try await libraryItems(
                    query,
                    startIndex: startIndex,
                    limit: limit,
                    includeTotalCount: includeTotalCount,
                )
            }
        }
        let shuffled = ShuffledPages { [self] in
            try await libraryItemIDs(query)
        } items: { [self] ids in
            try await libraryItems(ids: ids)
        }
        return { startIndex, limit, includeTotalCount in
            let page = try await shuffled.page(startIndex: startIndex, limit: limit)
            return LibraryPage(items: page.items, totalCount: includeTotalCount ? page.count : nil)
        }
    }

    /// The IDs of everything a library grid lists, by name, for a random order to be drawn from.
    func libraryItemIDs(_ query: LibraryQuery) async throws -> [MediaItem.ID] {
        var byName = query
        byName.sort = .default
        return try await itemIDs(byName.itemsParameters(userID: userID))
    }

    /// The grid entries with these IDs, as `libraryItems` describes them, in the order given. Any
    /// the server no longer has are left out.
    func libraryItems(ids: [MediaItem.ID]) async throws -> [LibraryEntry] {
        guard !ids.isEmpty else { return [] }
        var parameters = Paths.GetItemsParameters(userID: userID)
        parameters.ids = ids
        parameters.fields = LibraryEntry.fields
        parameters.enableImageTypes = LibraryEntry.imageTypes
        parameters.imageTypeLimit = 1
        let result = try await send(Paths.getItems(parameters: parameters))
        let found = (result.items ?? []).compactMap(LibraryEntry.init)
        let byID = Dictionary(found.map { ($0.id, $0) }) { first, _ in first }
        return ids.compactMap { byID[$0] }
    }
}

extension JellyfinSession {
    /// How many IDs one request asks for.
    static let itemIDPageSize = 1000

    /// The IDs of every item `parameters` matches, in its order, a page at a time, with nothing
    /// else the server can leave out: no images, user data or extra fields (Jellyfin adds none
    /// unless `fields` asks for them) and no total count, so a large library stays quick.
    ///
    /// - Parameter keep: whether to keep an item, for items the server sends that the caller
    ///   doesn't list.
    func itemIDs(
        _ parameters: Paths.GetItemsParameters,
        pageSize: Int = itemIDPageSize,
        keep: (BaseItemDto) -> Bool = { _ in true },
    ) async throws -> [MediaItem.ID] {
        var parameters = parameters
        parameters.fields = nil
        parameters.enableImages = false
        parameters.enableUserData = false
        parameters.enableTotalRecordCount = false
        parameters.limit = pageSize
        var ids: [MediaItem.ID] = []
        var seen: Set<MediaItem.ID> = []
        var startIndex = 0
        while true {
            parameters.startIndex = startIndex
            let items = try await send(Paths.getItems(parameters: parameters)).items ?? []
            // An item added or removed between pages can shift one onto the next page twice.
            for item in items where keep(item) {
                if let id = item.id, seen.insert(id).inserted {
                    ids.append(id)
                }
            }
            guard items.count >= pageSize else { return ids }
            startIndex += items.count
        }
    }
}
