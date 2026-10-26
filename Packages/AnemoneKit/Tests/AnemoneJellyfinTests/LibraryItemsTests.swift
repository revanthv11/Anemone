import AnemoneJellyfin
import Foundation
import Synchronization
import Testing

struct LibraryItemsTests {
    private let movies = Library(id: "lib-movies", name: "Movies", kind: .movies)
    private let shows = Library(id: "lib-shows", name: "Shows", kind: .shows)
    private let folder = Library(id: "lib-folder", name: "Home videos", kind: .homeVideos)

    // MARK: Paging

    @Test func `asks for one page with the grid's fields and the total only when told to`() async throws {
        let sent = recordItemsRequests(host: "page.test", total: 1234)

        let first = try await session(host: "page.test")
            .libraryItems(LibraryQuery(library: movies), startIndex: 0, limit: 100, includeTotalCount: true)
        let later = try await session(host: "page.test")
            .libraryItems(LibraryQuery(library: movies), startIndex: 300, limit: 100)

        #expect(first.totalCount == 1234)
        #expect(later.totalCount == nil)
        #expect(first.items.map(\.item.name) == ["Item 0", "Item 1"])
        #expect(first.items.first?.sortName == "item 0")
        let queries = sent.withLock { $0 }
        #expect(queries.map { $0["startIndex"] } == [["0"], ["300"]])
        #expect(queries.map { $0["limit"] } == [["100"], ["100"]])
        #expect(queries.map { $0["enableTotalRecordCount"] } == [["true"], ["false"]])
        #expect(queries[0]["fields"] == ["SortName"])
        #expect(queries[0]["parentId"] == ["lib-movies"])
        #expect(queries[0]["excludeItemIds"] == ["lib-movies"])
    }

    @Test func `movie and TV libraries list their titles from every folder`() async throws {
        let sent = recordItemsRequests(host: "types.test")

        for library in [movies, shows, folder] {
            _ = try await session(host: "types.test")
                .libraryItems(LibraryQuery(library: library), startIndex: 0, limit: 1)
        }

        let queries = sent.withLock { $0 }
        #expect(queries.map { $0["includeItemTypes"] } == [["Movie"], ["Series"], nil])
        #expect(queries.map { $0["recursive"] } == [["true"], ["true"], ["false"]])
    }

    // MARK: Sorting

    @Test func `sorts by the chosen field, then name, then year for movies`() async throws {
        let sent = recordItemsRequests(host: "sort.test")

        let byRating = LibraryQuery(library: movies, sort: LibrarySort(.communityRating, .descending))
        let byName = LibraryQuery(library: shows, sort: LibrarySort(.name, .descending))
        let serverOrder = LibraryQuery(library: folder, sort: LibrarySort(.default))
        for query in [byRating, byName, serverOrder] {
            _ = try await session(host: "sort.test").libraryItems(query, startIndex: 0, limit: 1)
        }

        let queries = sent.withLock { $0 }
        #expect(queries[0]["sortBy"] == ["CommunityRating", "SortName", "ProductionYear"])
        #expect(queries[0]["sortOrder"] == ["Descending", "Ascending", "Ascending"])
        #expect(queries[1]["sortBy"] == ["SortName"])
        #expect(queries[1]["sortOrder"] == ["Descending"])
        #expect(queries[2]["sortBy"] == nil)
        #expect(queries[2]["sortOrder"] == nil)
    }

    @Test func `choosing the current sort field reverses it`() {
        let sort = LibrarySort.default

        #expect(sort.choosing(.name) == LibrarySort(.name, .descending))
        #expect(sort.choosing(.dateCreated) == LibrarySort(.dateCreated, .ascending))
        #expect(sort.reversed.choosing(.runtime) == LibrarySort(.runtime, .descending))
    }

    @Test func `offers Wholphin's sorts and filters for each kind of library`() {
        #expect(movies.sortFields.first == .name)
        #expect(movies.sortFields.contains(.runtime))
        #expect(!movies.sortFields.contains(.dateLastContentAdded))
        #expect(shows.sortFields.contains(.dateLastContentAdded))
        #expect(shows.sortFields.contains(.seriesDatePlayed))
        #expect(Library(id: "p", name: "Playlists", kind: .playlists).sortFields.first == .default)
        #expect(shows.filterKinds.contains(.studios))
        #expect(!movies.filterKinds.contains(.studios))
    }

    // MARK: Filtering

    @Test func `maps each filter onto the items query`() async throws {
        let sent = recordItemsRequests(host: "filter.test")
        var filter = LibraryFilter()
        filter.played = false
        filter.favorite = true
        filter.genres = ["g2", "g1"]
        filter.studios = ["s1"]
        filter.minCommunityRating = 7
        filter.officialRatings = ["PG-13", "PG"]
        filter.years = [1985]
        filter.decades = [1990]

        _ = try await session(host: "filter.test")
            .libraryItems(LibraryQuery(library: movies, filter: filter), startIndex: 0, limit: 1)

        let query = try #require(sent.withLock { $0.first })
        #expect(query["isPlayed"] == ["false"])
        #expect(query["isFavorite"] == ["true"])
        #expect(query["genreIds"] == ["g1", "g2"])
        #expect(query["studioIds"] == ["s1"])
        #expect(query["minCommunityRating"] == ["7.0"])
        #expect(query["officialRatings"] == ["PG", "PG-13"])
        #expect(query["years"] == ["1985"] + (1990 ... 1999).map(String.init))
        #expect(query["is4K"] == nil)
        #expect(query["videoTypes"] == nil)
    }

    @Test(arguments: [
        ([LibraryFilter.VideoType.fourK], ["is4K": ["true"]]),
        ([.standardDefinition], ["isHd": ["false"]]),
        ([.highDefinition, .standardDefinition], ["isHd": ["true"]]),
        ([.threeD, .bluRay, .dvd], ["is3D": ["true"], "videoTypes": ["BluRay", "Dvd"]]),
    ])
    func `maps video type filters to resolution flags and disc types`(
        types: [LibraryFilter.VideoType],
        expected: [String: [String]],
    ) async throws {
        let host = "video-\(types.map(\.rawValue).joined(separator: "-")).test".lowercased()
        let sent = recordItemsRequests(host: host)
        var filter = LibraryFilter()
        filter.videoTypes = Set(types)

        _ = try await session(host: host)
            .libraryItems(LibraryQuery(library: movies, filter: filter), startIndex: 0, limit: 1)

        let query = try #require(sent.withLock { $0.first })
        let videoKeys = ["is4K", "isHd", "is3D", "videoTypes"]
        #expect(query.filter { videoKeys.contains($0.key) } == expected)
    }

    @Test func `counts and clears filters by kind`() {
        var filter = LibraryFilter()
        #expect(filter.isEmpty)
        filter.played = true
        filter.genres = ["g1"]
        filter.decades = [2000]

        #expect(filter.activeCount == 3)
        #expect(filter.isActive(.genres))
        #expect(!filter.isActive(.studios))
        #expect(filter.cleared(.genres).activeCount == 2)
        #expect(filter.cleared(.played).cleared(.genres).cleared(.decade).isEmpty)
    }

    @Test func `filters survive a round trip through JSON`() throws {
        var filter = LibraryFilter()
        filter.favorite = true
        filter.videoTypes = [.fourK, .dvd]
        filter.years = [2001]

        let decoded = try JSONDecoder().decode(LibraryFilter.self, from: JSONEncoder().encode(filter))

        #expect(decoded == filter)
    }

    // MARK: Filter values

    @Test func `loads genre, studio, year and rating choices for a library`() async throws {
        let sent = Mutex<[String: [String: [String]]]>([:])
        MockServer.register(host: "values.test") { request in
            let path = request.url?.path() ?? ""
            sent.withLock { $0[path] = request.queryValues }
            switch path {
            case "/Genres":
                return .json(#"{"Items":[{"Id":"g1","Name":"Drama"},{"Id":"g2","Name":"Comedy"}]}"#)
            case "/Studios":
                return .json(#"{"Items":[{"Id":"s1","Name":"HBO"}]}"#)
            case "/Years":
                return .json(#"{"Items":[{"Name":"2003"},{"Name":"1999"},{"Name":"1991"},{"Name":"oops"}]}"#)
            case "/Items/Filters":
                return .json(#"{"OfficialRatings":["R","G","PG-13","NR"]}"#)
            case "/Localization/ParentalRatings":
                return .json(#"""
                [{"Name":"G","Value":0},{"Name":"PG-13","Value":13},
                 {"Name":"R","RatingScore":{"score":17}},{"Name":"NR","Value":1000}]
                """#)
            default:
                return nil
            }
        }
        let session = try session(host: "values.test")

        let genres = try await session.genres(in: shows)
        let studios = try await session.studios(in: shows)
        let years = try await session.years(in: shows)
        let ratings = try await session.officialRatings(in: shows)

        #expect(genres == [FilterOption(id: "g1", name: "Drama"), FilterOption(id: "g2", name: "Comedy")])
        #expect(studios == [FilterOption(id: "s1", name: "HBO")])
        #expect(years == [1991, 1999, 2003])
        #expect(LibraryFilter.decades(of: years) == [1990, 2000])
        #expect(ratings == ["G", "PG-13", "R", "NR"])
        let queries = sent.withLock { $0 }
        #expect(queries["/Genres"]?["parentId"] == ["lib-shows"])
        #expect(queries["/Studios"]?["includeItemTypes"] == ["Series"])
        #expect(queries["/Items/Filters"]?["parentId"] == ["lib-shows"])
    }

    // MARK: Alphabet bar

    @Test func `jumps to a letter by counting the items before it with the grid's query`() async throws {
        let sent = recordItemsRequests(host: "jump.test", total: 40)
        var filter = LibraryFilter()
        filter.favorite = true
        let query = LibraryQuery(library: movies, filter: filter)

        let position = try await session(host: "jump.test").position(of: "M", in: query, count: 500)

        #expect(position == 40)
        let sentQuery = try #require(sent.withLock { $0.first })
        #expect(sentQuery["nameLessThan"] == ["m"])
        #expect(sentQuery["limit"] == ["0"])
        #expect(sentQuery["enableTotalRecordCount"] == ["true"])
        #expect(sentQuery["isFavorite"] == ["true"])
        #expect(sentQuery["sortBy"] == ["SortName", "ProductionYear"])
    }

    @Test func `jumping to # goes to the top without asking the server`() async throws {
        let sent = recordItemsRequests(host: "jump-top.test", total: 40)

        let position = try await session(host: "jump-top.test")
            .position(of: "#", in: LibraryQuery(library: movies), count: 500)

        #expect(position == 0)
        #expect(sent.withLock { $0.isEmpty })
    }

    @Test func `sorted Z to A, a letter starts after everything filed under later letters`() async throws {
        let sent = recordItemsRequests(host: "jump-desc.test", total: 460)
        let query = LibraryQuery(library: movies, sort: LibrarySort(.name, .descending))

        let atM = try await session(host: "jump-desc.test").position(of: "M", in: query, count: 500)
        let atZ = try await session(host: "jump-desc.test").position(of: "Z", in: query, count: 500)
        let atDigits = try await session(host: "jump-desc.test").position(of: "#", in: query, count: 500)

        // 460 items sort below "n", so the 40 from "n" to the end come first.
        #expect(atM == 40)
        #expect(atZ == 40)
        #expect(atDigits == 40)
        #expect(sent.withLock { $0.map { $0["nameLessThan"] } } == [["n"], ["{"], ["a"]])
    }

    @Test(arguments: [
        ("matrix", "M"), ("12 monkeys", "#"), ("Alien", "A"), ("été", nil), ("", nil), (nil, nil),
    ] as [(String?, Character?)])
    func `files items under a letter by sort name`(sortName: String?, letter: Character?) {
        #expect(LibraryJump.letter(for: sortName) == letter)
    }

    // MARK: Helpers

    private func session(host: String) throws -> JellyfinSession {
        try JellyfinSession(
            serverURL: #require(URL(string: "https://\(host)")),
            userID: "u1",
            accessToken: "tok",
            identity: ClientIdentity(deviceName: "Test TV", deviceID: "device-1", appVersion: "0.1.0"),
            sessionConfiguration: { MockServer.sessionConfiguration() },
        )
    }

    /// Answers `/Items` with two items and `total` as the count, recording each query.
    private func recordItemsRequests(host: String, total: Int = 2) -> QueryLog {
        let sent = QueryLog()
        MockServer.register(host: host) { request in
            guard request.url?.path() == "/Items" else { return nil }
            sent.withLock { $0.append(request.queryValues) }
            return .json(#"""
            {"Items":[
              {"Id":"i0","Name":"Item 0","SortName":"item 0","Type":"Movie"},
              {"Id":"i1","Name":"Item 1","SortName":"item 1","Type":"Movie"}
            ],"TotalRecordCount":\#(total)}
            """#)
        }
        return sent
    }
}

/// The queries a fake server received, in order.
private final class QueryLog: Sendable {
    private let queries = Mutex<[[String: [String]]]>([])

    func withLock<Result>(_ body: (inout [[String: [String]]]) -> Result) -> Result {
        queries.withLock { body(&$0) }
    }
}

private extension URLRequest {
    /// Every value of each query parameter, in order; the SDK repeats a key for each list item.
    var queryValues: [String: [String]] {
        let items = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        return Dictionary(grouping: items, by: \.name).mapValues { $0.map { $0.value ?? "" } }
    }
}
