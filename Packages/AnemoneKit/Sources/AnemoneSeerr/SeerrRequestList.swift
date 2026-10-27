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
    /// with the latest sign-in. Reloading and reading on take turns: each waits for the one
    /// before to finish, so neither reads from a place the other is about to move.
    @MainActor
    @Observable
    public final class SeerrRequestList {
        /// How near the end focus gets before the next page is read: two rows of the grid.
        public static let lookahead = 12

        /// Reads the page of `take` requests from the `skip`th, without looking up the titles in
        /// `known`: `SeerrConnection.requests(skip:take:known:)`, or a stand-in in tests.
        typealias Reader = @Sendable (
            _ skip: Int,
            _ take: Int,
            _ known: [DiscoverItem.ID: DiscoverItem],
        ) async throws -> SeerrRequestsPage

        /// The requests read so far whose titles were found, newest first; `nil` until the first
        /// page is read.
        public private(set) var items: [SeerrRequestedItem]?
        /// How many requests have been read, found or not.
        @ObservationIgnored private var end = 0
        @ObservationIgnored private var hasMore = false
        @ObservationIgnored private let pageSize: Int
        /// The titles found so far, by `DiscoverItem.id`, so reading a request again doesn't look
        /// its title up again.
        @ObservationIgnored private var titles: [DiscoverItem.ID: DiscoverItem] = [:]
        /// The latest reload's or read's turn, which the next waits for. It ends once that reload
        /// or read has, and every turn before it.
        @ObservationIgnored private var latest: Task<Void, Never>?

        public init(pageSize: Int = SeerrConnection.requestsPageSize) {
            self.pageSize = pageSize
        }

        /// Reads the list again from the start, a page at a time, as far as it had been read, so
        /// coming back to the page keeps the user's place. Only titles not found before are
        /// looked up.
        public func reload(from connection: SeerrConnection) async throws {
            try await reload(reading: Self.reader(connection))
        }

        /// Reads the next page once the request `id` is among the last `lookahead` shown, so it's
        /// there before focus reaches the end.
        public func readMore(near id: SeerrRequestedItem.ID, from connection: SeerrConnection) async throws {
            try await readMore(near: id, reading: Self.reader(connection))
        }

        func reload(reading read: @escaping Reader) async throws {
            try await inTurn { try await self.refresh(read) }
        }

        func readMore(near id: SeerrRequestedItem.ID, reading read: @escaping Reader) async throws {
            try await inTurn {
                // Checked in turn, against the list as the reads before left it.
                guard let items = self.items, self.hasMore,
                      let index = items.firstIndex(where: { $0.id == id }),
                      items.count - index <= Self.lookahead
                else { return }
                try await self.readNext(read)
            }
        }

        /// Runs `work` once the reload or read before it has finished. Cancelling the caller
        /// cancels `work`, and while it's still waiting for its turn, throws at once.
        private func inTurn(_ work: @escaping @MainActor @Sendable () async throws -> Void) async throws {
            let previous = latest
            let task = Task { @MainActor in
                try await Self.wait(for: previous)
                try await work()
            }
            // The next turn waits for this one and the one before it, so turns never overlap,
            // even when this one stopped waiting because it was cancelled.
            latest = Task {
                await previous?.value
                _ = await task.result
            }
            try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
        }

        /// Waits for `turn` to end, or throws `CancellationError` as soon as the task is
        /// cancelled: waiting for a task's value goes on through a cancellation.
        private static func wait(for turn: Task<Void, Never>?) async throws {
            if let turn {
                let (ended, end) = AsyncStream<Never>.makeStream()
                Task {
                    await turn.value
                    end.finish()
                }
                // Ends when the turn has, or at once when this task is cancelled.
                for await _ in ended {}
            }
            try Task.checkCancellation()
        }

        /// Reads the pages read so far again. Each page replaces the requests it covers as it
        /// comes in, and those after it stay until their own page comes in, so the grid doesn't
        /// shrink or lose focus while the rest load.
        private func refresh(_ read: Reader) async throws {
            let reach = max(end, pageSize)
            let before = items ?? []
            var fresh: [SeerrRequestedItem] = []
            var position = 0
            var more = true
            repeat {
                let page = try await readPage(at: position, read)
                // A request made meanwhile moves the rest down, so a page can repeat the last one.
                let shown = Set(fresh.map(\.id))
                fresh += page.items.filter { !shown.contains($0.id) }
                position = page.end
                more = page.hasMore
                items = fresh + Self.rest(of: before, after: fresh)
            } while more && position < reach
            items = fresh
            end = position
            hasMore = more
            if fresh.isEmpty {
                try await readNext(read)
            }
        }

        /// Reads the next page, and on past any whose titles were all left out, so focus has
        /// something new to reach.
        private func readNext(_ read: Reader) async throws {
            while hasMore, let items {
                let page = try await readPage(at: end, read)
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

        /// Reads the page from the `skip`th request, and keeps its titles for next time.
        private func readPage(at skip: Int, _ read: Reader) async throws -> SeerrRequestsPage {
            let page = try await read(skip, pageSize, titles)
            // Cancelled while looking titles up, a page leaves out the titles it didn't get to.
            try Task.checkCancellation()
            for item in page.items {
                titles[item.item.id] = item.item
            }
            return page
        }

        /// The requests of `before` that a refresh hasn't reached yet: those after the last one
        /// it has read again.
        private static func rest(
            of before: [SeerrRequestedItem],
            after fresh: [SeerrRequestedItem],
        ) -> [SeerrRequestedItem] {
            let read = Set(fresh.map(\.id))
            let start = before.lastIndex { read.contains($0.id) }.map { $0 + 1 } ?? 0
            return before[start...].filter { !read.contains($0.id) }
        }

        private static func reader(_ connection: SeerrConnection) -> Reader {
            { skip, take, known in
                try await connection.requests(skip: skip, take: take, known: known)
            }
        }
    }
#endif
