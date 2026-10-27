import Foundation

/// The guide's bookkeeping for loading listings a page of channels at a time: which pages have
/// been asked for, and which answer for each page is the newest. Loads of one page can land out
/// of order (a row's first load and a reload after a recording changed, or two quick reloads),
/// and an older answer landing last would put back stale recording markers; so each load gets a
/// number, and an answer goes up only when no later load of its page has gone up already.
public struct LiveTVListingPages: Sendable {
    /// One load of a page's listings.
    public struct Load: Hashable, Sendable {
        public let page: Int
        /// The guide it was asked for under; a new channel list or guide makes it stale.
        let generation: Int
        /// When it was asked for, among every load.
        let sequence: Int
    }

    /// Channels whose listings one load asks for.
    public let pageSize: Int
    /// The pages asked for so far, under the guide showing.
    public private(set) var requested: Set<Int> = []
    private var generation = 0
    private var sequence = 0
    /// The load each page's rows show, under the guide showing.
    private var shown: [Int: Int] = [:]
    /// The last load asked for of each page.
    private var latest: [Int: Int] = [:]

    public init(pageSize: Int) {
        self.pageSize = pageSize
    }

    /// The page holding the channel at `index`.
    public func page(ofChannelAt index: Int) -> Int {
        index / pageSize
    }

    /// Starts a load of `page`.
    public mutating func start(_ page: Int) -> Load {
        sequence += 1
        latest[page] = sequence
        return Load(page: page, generation: generation, sequence: sequence)
    }

    /// The first load of the page holding the row at `index`, as the row comes on screen; `nil`
    /// once that page has been asked for.
    public mutating func firstLoad(forRow index: Int) -> Load? {
        let page = page(ofChannelAt: index)
        guard requested.insert(page).inserted else { return nil }
        return start(page)
    }

    /// The loads to make after a recording was set or cancelled. A single programme's recording
    /// marks only that programme, so only the page holding its channel (at `channelIndex`) loads
    /// again, if it has been asked for; a series recording marks programmes on any channel, so
    /// every page asked for loads again, as it does when the channel isn't known (`nil`).
    public mutating func reloads(channelIndex: Int?) -> [Load] {
        let pages = channelIndex.map { requested.intersection([page(ofChannelAt: $0)]) } ?? requested
        return pages.sorted().map { start($0) }
    }

    /// A new channel list or guide went up, showing `load`'s listings for its page. Every load
    /// asked for under the old one is now stale; the other pages that had been asked for start
    /// again, and so does `load`'s own page when it was asked for again after `load` (a reload
    /// after a recording changed, whose answer is now dropped). Their loads are returned.
    public mutating func startOver(showing load: Load) -> [Load] {
        let overtaken = latest[load.page, default: 0] > load.sequence
        generation += 1
        let others = requested.subtracting([load.page])
        requested = [load.page]
        shown = [load.page: load.sequence]
        let again = others.sorted().compactMap { firstLoad(forRow: $0 * pageSize) }
        return overtaken ? [start(load.page)] + again : again
    }

    /// Whether `load`'s answer goes up: it's for the guide showing, and no load of its page asked
    /// for later has gone up. Once it's accepted, it's the one its page shows.
    public mutating func accept(_ load: Load) -> Bool {
        guard load.generation == generation, load.sequence > shown[load.page, default: 0] else { return false }
        shown[load.page] = load.sequence
        return true
    }

    /// A load failed. A page with nothing up yet shows no data, so it's asked for again when its
    /// row next comes on screen; one that shows listings keeps them.
    public mutating func failed(_ load: Load) {
        guard load.generation == generation, shown[load.page] == nil else { return }
        requested.remove(load.page)
    }
}
