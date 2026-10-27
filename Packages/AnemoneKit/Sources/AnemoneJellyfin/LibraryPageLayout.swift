import Foundation

/// The pages of a list loaded so far, and where each item sits, for `LibraryPager` and
/// `SlideshowPager`.
///
/// A page can come back with fewer items than the first page's count said: some were removed
/// since, or couldn't be read (a random grid's or a shuffled slideshow's pages are fetched by
/// ID, which leaves out those the server no longer has). Such a page closes up: the items after
/// it move up and `count` goes down, so no place waits for an item that will never come. Pages
/// not loaded yet are taken to be full.
///
/// Items deleted from the app close up the same way (`remove(where:)`), and since the loader's
/// list has lost them too, the pages after them are asked for that much earlier
/// (`startIndex(ofPage:)`), so none of the items that moved up is skipped.
struct PagedItems<Item> {
    let pageSize: Int
    /// How many items the first page counted, which the loader's pages are counted in.
    private(set) var counted = 0
    /// How many items there are: `counted`, less any that the pages loaded since left out.
    private(set) var count = 0
    private var pages: [Int: [Item]] = [:]
    /// Where each page starts.
    private var starts: [Int] = []
    /// How many items `remove(where:)` took out of each loaded page.
    private var removed: [Int: Int] = [:]

    init(pageSize: Int) {
        self.pageSize = pageSize
    }

    /// The loader's pages, loaded or not.
    var pageCount: Int {
        starts.count
    }

    /// Starts again from the first page and the count it gave.
    mutating func start(_ first: [Item], counted: Int) {
        self.counted = counted
        pages = [0: first]
        removed = [:]
        layOut()
    }

    /// Whether the loader has a page `page`.
    func hasPage(_ page: Int) -> Bool {
        page >= 0 && page < pageCount
    }

    func items(onPage page: Int) -> [Item]? {
        pages[page]
    }

    /// Keeps a page that has loaded, unless it's here already, and lays the rest out after it.
    mutating func set(_ items: [Item], onPage page: Int) {
        guard hasPage(page), pages[page] == nil else { return }
        pages[page] = items
        layOut()
    }

    /// The item at `index`, or `nil` while its page is loading.
    func item(at index: Int) -> Item? {
        guard let page = page(holding: index), let items = pages[page] else { return nil }
        let offset = index - starts[page]
        return items.indices.contains(offset) ? items[offset] : nil
    }

    /// The page holding `index`, loaded or not.
    func page(holding index: Int) -> Int? {
        guard index >= 0, index < count else { return nil }
        // The last page starting at or before `index`, which passes over any that came back empty.
        var low = 0
        var high = starts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if starts[middle] <= index {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return low
    }

    /// Where the `offset`th item of `page` is.
    func index(of offset: Int, onPage page: Int) -> Int {
        starts[page] + offset
    }

    /// Where the loader's list has `page` now: its place in the list the first page counted, less
    /// the items removed from the pages before it, which the list no longer has either.
    func startIndex(ofPage page: Int) -> Int {
        page * pageSize - removed.reduce(0) { $1.key < page ? $0 + $1.value : $0 }
    }

    /// Takes the matching items out of the pages loaded so far, as when they were deleted, and
    /// returns how many went. The items after them move up, as after a page that came back short.
    /// Pages not loaded yet are left alone: the loader leaves deleted items out of them.
    @discardableResult
    mutating func remove(where isRemoved: (Item) -> Bool) -> Int {
        var total = 0
        for (page, items) in pages {
            let kept = items.filter { !isRemoved($0) }
            guard kept.count < items.count else { continue }
            pages[page] = kept
            removed[page, default: 0] += items.count - kept.count
            total += items.count - kept.count
        }
        if total > 0 {
            layOut()
        }
        return total
    }

    private mutating func layOut() {
        let pageCount = (counted + pageSize - 1) / pageSize
        var starts: [Int] = []
        starts.reserveCapacity(pageCount)
        var next = 0
        for page in 0 ..< pageCount {
            starts.append(next)
            next += pages[page]?.count ?? min(pageSize, counted - page * pageSize)
        }
        self.starts = starts
        count = next
    }
}
