#if ANEMONE_SEERR
    @testable import AnemoneSeerr
    import Foundation
    import Synchronization
    import Testing

    @MainActor
    struct SeerrRequestListTests {
        /// A Seerr whose requests are `ids()`, newest first, each for the movie of the same TMDB
        /// ID, paged by `take` and `skip` as Seerr pages them. The movies in `missing` can't be
        /// found.
        private static func requests(
            _ ids: @escaping @Sendable () -> [Int],
            missing: Set<Int> = [],
        ) -> @Sendable (Sent) -> SeerrMockServer.Reply? {
            { request in
                let moviePath = "/api/v1/movie/"
                if request.path == "/api/v1/request" {
                    let all = ids()
                    let skip = Int(request.query["skip"] ?? "") ?? 0
                    let take = Int(request.query["take"] ?? "") ?? 10
                    let results = all.dropFirst(skip).prefix(take).map {
                        #"{"id":\#($0),"status":1,"type":"movie","media":{"tmdbId":\#($0)},"requestedBy":{"id":7}}"#
                    }
                    return .json(#"""
                    {"pageInfo":{"page":1,"pages":1,"results":\#(all.count)},
                     "results":[\#(results.joined(separator: ","))]}
                    """#)
                }
                if request.path.hasPrefix(moviePath), let id = Int(request.path.dropFirst(moviePath.count)),
                   !missing.contains(id)
                {
                    return .json(#"{"id":\#(id),"title":"Movie \#(id)"}"#)
                }
                return .status(404)
            }
        }

        /// The `skip` and `take` of each page asked of `host`.
        private func pages(asked host: String) -> [[String?]] {
            SeerrMockServer.requests(to: host)
                .filter { $0.path == "/api/v1/request" }
                .map { [$0.query["skip"], $0.query["take"]] }
        }

        /// How many titles `host` was asked for.
        private func lookups(asked host: String) -> Int {
            SeerrMockServer.requests(to: host).count { $0.path.hasPrefix("/api/v1/movie/") }
        }

        @Test func `the Requests list reads a page at a time as focus nears its end`() async throws {
            let host = "paging.seerr.test"
            let ids = Mutex(Array((1 ... 45).reversed()))
            let seerr = try await connection(to: host, other: Self.requests { ids.withLock { $0 } })
            let list = SeerrRequestList()

            try await list.reload(from: seerr)
            #expect(list.items?.map(\.id) == Array((26 ... 45).reversed()))

            // Focus on the first rows doesn't read on; the last two rows do.
            try await list.readMore(near: 45, from: seerr)
            try await list.readMore(near: 38, from: seerr)
            #expect(list.items?.count == 20)
            try await list.readMore(near: 37, from: seerr)
            #expect(list.items?.map(\.id) == Array((6 ... 45).reversed()))
            try await list.readMore(near: 6, from: seerr)
            #expect(list.items?.map(\.id) == Array((1 ... 45).reversed()))
            // That was the last page.
            try await list.readMore(near: 1, from: seerr)

            #expect(pages(asked: host) == [["0", "20"], ["20", "20"], ["40", "20"]])
            #expect(lookups(asked: host) == 45)

            // Coming back to the page reads as far as before, a page at a time, and looks up only
            // the title of a request made since.
            ids.withLock { $0.insert(46, at: 0) }
            try await list.reload(from: seerr)
            #expect(list.items?.map(\.id) == Array((1 ... 46).reversed()))
            #expect(pages(asked: host).suffix(3) == [["0", "20"], ["20", "20"], ["40", "20"]])
            #expect(lookups(asked: host) == 46)
        }

        @Test func `pages whose titles are all missing are read past`() async throws {
            let host = "missing.seerr.test"
            let seerr = try await connection(to: host, other: Self.requests({ [6, 5, 4, 3, 2, 1] }, missing: [6, 5, 4]))
            let list = SeerrRequestList(pageSize: 2)

            try await list.reload(from: seerr)

            #expect(list.items?.map(\.id) == [3])
            #expect(pages(asked: host) == [["0", "2"], ["2", "2"]])
        }

        @Test func `a request made meanwhile isn't shown twice`() async throws {
            let host = "shifting.seerr.test"
            let ids = Mutex([5, 4, 3, 2, 1])
            let seerr = try await connection(to: host, other: Self.requests { ids.withLock { $0 } })
            let list = SeerrRequestList(pageSize: 2)

            try await list.reload(from: seerr)
            ids.withLock { $0.insert(6, at: 0) }
            try await list.readMore(near: 4, from: seerr)

            #expect(list.items?.map(\.id) == [5, 4, 3])
        }

        @Test func `a reload waits for a read under way, then reads as far as it got`() async throws {
            let pages = HeldPages(Array((1 ... 45).reversed()))
            let list = SeerrRequestList()
            try await list.reload(reading: pages.reader)
            pages.hold(20)

            let more = Task { try await list.readMore(near: 37, reading: pages.reader) }
            #expect(await pages.nextHeld() == 20)
            let reload = Task { try await list.reload(reading: pages.reader) }
            // Plenty of chances for the reload to read before the read under way has finished.
            for _ in 0 ..< 50 {
                await Task.yield()
            }
            #expect(pages.skips == [0, 20])

            pages.release(20)
            try await more.value
            try await reload.value
            #expect(pages.skips == [0, 20, 0, 20])
            #expect(list.items?.map(\.id) == Array((6 ... 45).reversed()))
        }

        @Test func `a read waits for a reload under way, and reads on from where the reload got to`() async throws {
            let pages = HeldPages(Array((1 ... 45).reversed()))
            let list = SeerrRequestList()
            try await list.reload(reading: pages.reader)
            pages.hold(0)

            let reload = Task { try await list.reload(reading: pages.reader) }
            #expect(await pages.nextHeld() == 0)
            let more = Task { try await list.readMore(near: 37, reading: pages.reader) }
            for _ in 0 ..< 50 {
                await Task.yield()
            }
            #expect(pages.skips == [0, 0])

            pages.release(0)
            try await reload.value
            try await more.value
            #expect(pages.skips == [0, 0, 20])
            #expect(list.items?.map(\.id) == Array((6 ... 45).reversed()))
        }

        @Test func `a reload cancelled while it waits its turn ends at once, and the next still waits`() async throws {
            let pages = HeldPages(Array((1 ... 45).reversed()))
            let list = SeerrRequestList()
            try await list.reload(reading: pages.reader)
            pages.hold(20)
            let more = Task { try await list.readMore(near: 37, reading: pages.reader) }
            #expect(await pages.nextHeld() == 20)

            let ended = Flag()
            let cancelled = Task {
                defer { ended.isSet = true }
                try await list.reload(reading: pages.reader)
            }
            for _ in 0 ..< 10 {
                await Task.yield()
            }
            cancelled.cancel()

            // It ends while the read under way is still held, having read nothing.
            #expect(await eventually { ended.isSet })
            #expect(pages.skips == [0, 20])
            // A reload after it still waits for the read, not only for the cancelled one.
            let reload = Task { try await list.reload(reading: pages.reader) }
            for _ in 0 ..< 50 {
                await Task.yield()
            }
            #expect(pages.skips == [0, 20])

            pages.release(20)
            try await more.value
            try await reload.value
            await #expect(throws: CancellationError.self) { try await cancelled.value }
            #expect(pages.skips == [0, 20, 0, 20])
            #expect(list.items?.map(\.id) == Array((6 ... 45).reversed()))
        }

        @Test func `a reload shows each page as it comes in, keeping the rest until their page does`() async throws {
            let pages = HeldPages(Array((1 ... 45).reversed()))
            let list = SeerrRequestList()
            try await list.reload(reading: pages.reader)
            try await list.readMore(near: 37, reading: pages.reader)
            // A new request, and one withdrawn.
            pages.change { ids in
                ids.insert(46, at: 0)
                ids.removeAll { $0 == 30 }
            }
            pages.hold(20)

            let reload = Task { try await list.reload(reading: pages.reader) }
            #expect(await pages.nextHeld() == 20)
            // The first page is in; the requests after it wait for the second.
            let firstPage = [46] + Array((31 ... 45).reversed()) + Array((26 ... 29).reversed())
            #expect(list.items?.map(\.id) == firstPage + Array((6 ... 25).reversed()))

            pages.release(20)
            try await reload.value
            #expect(list.items?.map(\.id) == firstPage + Array((6 ... 25).reversed()))
            #expect(pages.skips.suffix(2) == [0, 20])
        }
    }

    /// Set once something has happened, for a test to wait on.
    @MainActor
    private final class Flag {
        var isSet = false
    }

    /// Whether `condition` holds within `timeout`, checking every millisecond.
    @MainActor
    private func eventually(timeout: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return true
    }

    /// A stand-in for Seerr's list of requests, `ids` newest first, each for the movie of the
    /// same TMDB ID, whose pages can be held back until a test lets them go.
    private final class HeldPages: Sendable {
        private struct State {
            var ids: [Int]
            var held: Set<Int> = []
            var waiting: [(skip: Int, continuation: CheckedContinuation<Void, Never>)] = []
            var skips: [Int] = []
        }

        private let state: Mutex<State>
        private let arrivals: AsyncStream<Int>
        private let arrived: AsyncStream<Int>.Continuation

        init(_ ids: [Int]) {
            state = Mutex(State(ids: ids))
            let stream = AsyncStream.makeStream(of: Int.self)
            arrivals = stream.stream
            arrived = stream.continuation
        }

        /// The `skip` of each page asked for, in order.
        var skips: [Int] {
            state.withLock { $0.skips }
        }

        var reader: SeerrRequestList.Reader {
            { [self] skip, take, _ in await read(skip: skip, take: take) }
        }

        /// Holds back the page from `skip` until it's released.
        func hold(_ skip: Int) {
            state.withLock { _ = $0.held.insert(skip) }
        }

        func release(_ skip: Int) {
            let waiting = state.withLock { state in
                state.held.remove(skip)
                let waiting = state.waiting.filter { $0.skip == skip }
                state.waiting.removeAll { $0.skip == skip }
                return waiting
            }
            for page in waiting {
                page.continuation.resume()
            }
        }

        func change(_ change: (inout [Int]) -> Void) {
            state.withLock { change(&$0.ids) }
        }

        /// The `skip` of the next held page asked for, once it has been.
        func nextHeld() async -> Int? {
            var iterator = arrivals.makeAsyncIterator()
            return await iterator.next()
        }

        private func read(skip: Int, take: Int) async -> SeerrRequestsPage {
            let isHeld = state.withLock { state in
                state.skips.append(skip)
                return state.held.contains(skip)
            }
            if isHeld {
                arrived.yield(skip)
            }
            await withCheckedContinuation { continuation in
                let isHeld = state.withLock { state in
                    if state.held.contains(skip) {
                        state.waiting.append((skip, continuation))
                        return true
                    }
                    return false
                }
                if !isHeld {
                    continuation.resume()
                }
            }
            let ids = state.withLock { $0.ids }
            let items = ids.dropFirst(skip).prefix(take).map {
                SeerrRequestedItem(
                    request: SeerrRequest(id: $0, status: .pending),
                    item: DiscoverItem(tmdbID: $0, kind: .movie, title: "Movie \($0)"),
                )
            }
            let end = skip + items.count
            return SeerrRequestsPage(items: items, end: end, hasMore: end < ids.count)
        }
    }
#endif
