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

        @Test func `the Requests list reads a page at a time as focus nears its end`() async throws {
            let host = "paging.seerr.test"
            let seerr = try await connection(to: host, other: Self.requests { Array((1 ... 45).reversed()) })
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

            // Coming back to the page reads as far as before, in one go.
            try await list.reload(from: seerr)
            #expect(list.items?.count == 45)
            #expect(pages(asked: host).last == ["0", "45"])
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
    }
#endif
