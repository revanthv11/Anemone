#if ANEMONE_SEERR
    import Foundation
    import Observation

    /// A page of the requests the user may see, from `SeerrConnection.requests(skip:take:)`.
    public struct SeerrRequestsPage: Hashable, Sendable {
        /// The page's requests whose titles were found, newest first.
        public var items: [SeerrRequestedItem]
        /// How far into the list the page reaches: the next page starts here.
        public var end: Int
        /// Whether Seerr has requests past `end`.
        public var hasMore: Bool

        public init(items: [SeerrRequestedItem], end: Int, hasMore: Bool) {
            self.items = items
            self.end = end
            self.hasMore = hasMore
        }
    }

    /// The Requests page's list, read a page at a time as focus nears its end, as Wholphin's
    /// Discover grids read theirs (`DiscoverRequestPager`). Wholphin's Requests page itself reads
    /// only the first page, so a user with more requests never sees the older ones.
    ///
    /// It's given the connection on each call rather than keeping one, so a page always reads
    /// with the latest sign-in.
    @MainActor
    @Observable
    public final class SeerrRequestList {
        /// How near the end focus gets before the next page is read: two rows of the grid.
        public static let lookahead = 12

        /// The requests read so far whose titles were found, newest first; `nil` until the first
        /// page is read.
        public private(set) var items: [SeerrRequestedItem]?
        /// How many requests have been read, found or not.
        @ObservationIgnored private var end = 0
        @ObservationIgnored private var hasMore = false
        @ObservationIgnored private var isReadingMore = false
        @ObservationIgnored private let pageSize: Int

        public init(pageSize: Int = SeerrConnection.requestsPageSize) {
            self.pageSize = pageSize
        }

        /// Reads the list again from the start, as far as it had been read, so coming back to the
        /// page keeps the user's place.
        public func reload(from connection: SeerrConnection) async throws {
            let page = try await connection.requests(take: max(end, pageSize))
            items = page.items
            end = page.end
            hasMore = page.hasMore
            if page.items.isEmpty {
                try await readNext(from: connection)
            }
        }

        /// Reads the next page once the request `id` is among the last `lookahead` shown, so it's
        /// there before focus reaches the end.
        public func readMore(near id: SeerrRequestedItem.ID, from connection: SeerrConnection) async throws {
            guard let items, hasMore, !isReadingMore,
                  let index = items.firstIndex(where: { $0.id == id }),
                  items.count - index <= Self.lookahead
            else { return }
            isReadingMore = true
            defer { isReadingMore = false }
            try await readNext(from: connection)
        }

        /// Reads the next page, and on past any whose titles were all left out, so focus has
        /// something new to reach.
        private func readNext(from connection: SeerrConnection) async throws {
            while hasMore {
                let start = end
                let page = try await connection.requests(skip: start, take: pageSize)
                // Reloaded meanwhile to somewhere else: this page doesn't follow on.
                guard end == start, let items else { return }
                // A request made meanwhile moves the rest down, so a page can repeat the last one.
                let shown = Set(items.map(\.id))
                self.items = items + page.items.filter { !shown.contains($0.id) }
                end = page.end
                hasMore = page.hasMore
                if !page.items.isEmpty {
                    return
                }
            }
        }
    }
#endif
