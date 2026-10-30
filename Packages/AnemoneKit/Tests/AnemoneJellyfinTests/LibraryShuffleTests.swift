import AnemoneJellyfin
import Foundation
import Testing

/// Library grids sorted at random, which hold one order while they're open.
@MainActor
struct LibraryShuffleTests {
    private let movies = Library(id: "lib-movies", name: "Movies", kind: .movies)

    @Test func `a random grid is shuffled once and paged by ID, showing each title once`() async throws {
        let count = 1250
        let sent = serveTitles(host: "random-grid.test", count: count)
        var filter = LibraryFilter()
        filter.played = false
        let query = LibraryQuery(library: movies, sort: LibrarySort(.random), filter: filter, scope: .genre("g1"))
        let pager = try LibraryPager(loader: librarySession(host: "random-grid.test").libraryLoader(for: query))

        try await pager.start()
        var shown: [MediaItem.ID] = []
        for index in 0 ..< pager.count {
            try shown.append(#require(await pager.load(at: index)).id)
        }

        #expect(pager.count == count)
        #expect(Set(shown) == Set((0 ..< count).map(Self.id)))
        #expect(shown.count == count)
        #expect(shown != (0 ..< count).map(Self.id))
        let requests = sent.requests.map(\.query)
        // Every ID first, a thousand at a time, as the grid asks for its titles but by name and
        // with nothing else: no random sort, images, user data or fields.
        let idRequests = requests.filter { $0["ids"] == nil }
        #expect(idRequests.count == 2)
        #expect(idRequests.map { $0["startIndex"] } == ["0", "1000"])
        for idRequest in idRequests {
            #expect(idRequest["limit"] == "1000")
            #expect(idRequest["sortBy"] == "SortName,ProductionYear")
            #expect(idRequest["genreIds"] == "g1")
            #expect(idRequest["isPlayed"] == "false")
            #expect(idRequest["includeItemTypes"] == "Movie")
            #expect(idRequest["parentId"] == "lib-movies")
            #expect(idRequest["enableImages"] == "false")
            #expect(idRequest["enableUserData"] == "false")
            #expect(idRequest["fields"] == nil)
        }
        // Then each page by ID, in the shuffled order, with the grid's fields.
        let pages = requests.filter { $0["ids"] != nil }
        let pageIDs = pages.map { ($0["ids"] ?? "").split(separator: ",").map(String.init) }
        #expect(pageIDs.map(\.count) == Array(repeating: 100, count: 12) + [50])
        #expect(pageIDs.flatMap(\.self) == shown)
        #expect(pages.allSatisfy { $0["fields"] == "SortName,Overview,CanDelete" && $0["sortBy"] == nil })
    }

    @Test func `a big random grid counts its IDs with the first page, then asks for the rest together`() async throws {
        let count = 5500
        let sent = serveTitles(host: "random-big.test", count: count)
        let query = LibraryQuery(library: movies, sort: LibrarySort(.random))

        let ids = try await librarySession(host: "random-big.test").libraryItemIDs(query)

        #expect(ids == (0 ..< count).map(Self.id))
        let requests = sent.requests.map(\.query)
        #expect(requests.count == 6)
        let first = try #require(requests.first)
        #expect(first["startIndex"] == "0")
        #expect(first["enableTotalRecordCount"] == "true")
        // Up to the count, in any order, since they go out together; none counted again.
        let rest = requests.dropFirst()
        #expect(Set(rest.map { $0["startIndex"] }) == ["1000", "2000", "3000", "4000", "5000"])
        #expect(rest.allSatisfy { $0["enableTotalRecordCount"] == "false" && $0["limit"] == "1000" })
    }

    @Test func `a random grid's page missing titles removed since closes up`() async throws {
        let gone: Set = [7, 120, 121, 249]
        _ = serveTitles(host: "random-gone.test", count: 250, gone: gone)
        let query = LibraryQuery(library: movies, sort: LibrarySort(.random))
        let pager = try LibraryPager(loader: librarySession(host: "random-gone.test").libraryLoader(for: query))

        try await pager.start()
        var shown: [MediaItem.ID] = []
        var index = 0
        while index < pager.count {
            try shown.append(#require(await pager.load(at: index)).id)
            index += 1
        }

        // No place is left waiting for a title the server no longer has.
        #expect(pager.count == 246)
        #expect(Set(shown) == Set((0 ..< 250).filter { !gone.contains($0) }.map(Self.id)))
        #expect(shown.count == 246)
    }

    @Test func `a random grid's pages keep their order when asked for again`() async throws {
        let sent = serveTitles(host: "random-again.test", count: 30)
        let query = LibraryQuery(library: movies, sort: LibrarySort(.random))
        let loader = try librarySession(host: "random-again.test").libraryLoader(for: query)

        let first = try await loader(0, 10, true)
        let second = try await loader(10, 10, false)
        let again = try await loader(0, 10, false)

        #expect(first.totalCount == 30)
        #expect(second.totalCount == nil)
        #expect(again.items.map(\.id) == first.items.map(\.id))
        #expect(Set(first.items.map(\.id)).isDisjoint(with: second.items.map(\.id)))
        // The IDs were asked for once.
        #expect(sent.requests.count(where: { $0.query["ids"] == nil }) == 1)
    }

    @Test func `a grid sorted otherwise pages through the server's order`() async throws {
        let sent = serveTitles(host: "sorted-grid.test", count: 30)
        let query = LibraryQuery(library: movies, sort: LibrarySort(.dateCreated, .descending))
        let loader = try librarySession(host: "sorted-grid.test").libraryLoader(for: query)

        _ = try await loader(10, 10, false)

        let request = try #require(sent.request)
        #expect(request.query["sortBy"] == "DateCreated,SortName,ProductionYear")
        #expect(request.query["startIndex"] == "10")
        #expect(request.query["ids"] == nil)
        #expect(sent.requests.count == 1)
    }

    // MARK: Helpers

    private nonisolated static func id(_ index: Int) -> MediaItem.ID {
        "m\(index)"
    }

    /// Answers `/Items` from `count` movies: a page of them by `startIndex` and `limit`, or those
    /// asked for by ID, in the server's order rather than the one asked for. Those in `gone` were
    /// removed after their IDs were listed, so asking for them by ID leaves them out.
    private func serveTitles(host: String, count: Int, gone: Set<Int> = []) -> Recorder {
        let sent = Recorder()
        MockServer.register(host: host) { request in
            let query = sent.record(request).query
            let indexes: [Int]
            if let ids = query["ids"] {
                indexes = ids.split(separator: ",").compactMap { Int($0.dropFirst()) }.filter { !gone.contains($0) }
                    .sorted()
            } else {
                let start = Int(query["startIndex"] ?? "") ?? 0
                let limit = Int(query["limit"] ?? "") ?? count
                indexes = Array(start ..< min(start + limit, count))
            }
            let items = indexes.map { #"{"Id":"\#(Self.id($0))","Name":"Movie \#($0)","Type":"Movie"}"# }
            return .json(#"{"Items":[\#(items.joined(separator: ","))],"TotalRecordCount":\#(count)}"#)
        }
        return sent
    }
}
