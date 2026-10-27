import AnemoneCore
@testable import AnemoneJellyfin
import Foundation
import Synchronization
import Testing

/// Loading the home page's rows.
struct HomeTests {
    @Test func `the default page combines watching rows and adds each library's newest items`() async throws {
        let server = HomeServer("home-default.test") { path, request in
            switch (path, request.query["parentId"]) {
            case ("/UserViews", _): .json(HomeFixtures.views)
            case ("/DisplayPreferences/default", _): .displayPreferences()
            case ("/UserItems/Resume", _): .homeItems(HomeFixtures.movie())
            case ("/Shows/NextUp", _): .homeItems()
            case ("/Items/Latest", "movies"): MockServer.Reply(status: 500, body: "")
            case ("/Items/Latest", "shows"): .json("[\(HomeFixtures.episode())]")
            default: nil
            }
        }

        let home = try await server.session().home()

        #expect(home.configs.map(\.kind) == [
            .continueWatchingCombined, .recentlyAdded(parentID: "movies"), .recentlyAdded(parentID: "shows"),
            .tvPrograms,
        ])
        #expect(home.rows.map(\.id) == ["continueWatching", "recentlyAdded.shows"])
        #expect(home.rows.map(\.title) == ["Continue Watching", "Recently Added in Shows"])
        // New episodes show as their series.
        #expect(home.rows.last?.items.map(\.id) == ["series"])
        #expect(home.failedRows == ["recentlyAdded.movies"])
        #expect(!server.paths.contains("/LiveTv/Programs"))
    }

    @Test func `the combined row puts what was watched most recently first`() async throws {
        let server = HomeServer("home-combined.test") { path, request in
            switch (path, request.query["adjacentTo"]) {
            case ("/UserViews", _): .json(#"{"Items":[]}"#)
            case ("/DisplayPreferences/default", _): .displayPreferences()
            case ("/UserItems/Resume", _): .homeItems(HomeFixtures.movie(lastPlayed: serverDate(daysAgo: 3)))
            case ("/Shows/NextUp", _):
                .homeItems(
                    HomeFixtures.episode("old", series: "s1"),
                    HomeFixtures.episode("new", series: "s2", premiere: serverDate(daysAgo: 1)),
                    HomeFixtures.episode("recent", series: "s3"),
                )
            // When the episode before each was played.
            case ("/Shows/s1/Episodes", "old"): .homeItems(HomeFixtures.episode(lastPlayed: serverDate(daysAgo: 10)))
            case ("/Shows/s2/Episodes", "new"): .homeItems(HomeFixtures.episode(lastPlayed: serverDate(daysAgo: 30)))
            case ("/Shows/s3/Episodes", "recent"): .homeItems(HomeFixtures.episode(lastPlayed: serverDate(daysAgo: 2)))
            default: nil
            }
        }

        let home = try await server.session().home(rows: [HomeRowConfig(.continueWatchingCombined)])

        // A new episode counts from its premiere, after the show's last watched episode.
        #expect(home.rows.first?.items.map(\.id) == ["new", "recent", "m1", "old"])
    }

    @Test(arguments: [
        ([String](), ["s1", "s2", "s3"]),
        (["s1"], ["s2", "s3"]),
        (["s2"], ["s1", "s3"]),
        (["s1", "s2"], ["s3"]),
    ])
    func `next up leaves out removed series until one of their episodes is played`(
        removed: [String],
        shown: [String],
    ) async throws {
        // Ported from Wholphin's `LatestNextUpServiceTests`: each series was removed a day ago.
        let dates = Dictionary(uniqueKeysWithValues: removed.map { (JellyfinID.compact($0), Date.now - 86400) })
        let removedJSON = try RemovedFromNextUp(dates: dates).json()
        let server = HomeServer("home-nextup\(removed.count)\(removed.joined()).test") { path, _ in
            switch path {
            case "/UserViews": .json(#"{"Items":[]}"#)
            case "/DisplayPreferences/default": .displayPreferences(["removeNextUp": removedJSON])
            case "/Shows/NextUp":
                .homeItems(
                    HomeFixtures.episode("e1", series: "s1", lastPlayed: serverDate(daysAgo: 7)),
                    HomeFixtures.episode("e2", series: "s2"),
                    HomeFixtures.episode("e3", series: "s3", lastPlayed: serverDate(daysAgo: -7)),
                )
            default: nil
            }
        }

        let home = try await server.session().home(rows: [HomeRowConfig(.nextUp)])

        #expect(home.rows.first?.items.compactMap(\.episode?.seriesID) ?? [] == shown)
        let sent = try #require(server.requests(to: "/Shows/NextUp").first)
        #expect(sent.query["enableResumable"] == "false")
        #expect(sent.query["enableRewatching"] == "false")
        let preferences = try #require(server.requests(to: "/DisplayPreferences/default").first)
        #expect(preferences.query["client"] == "Anemone")
    }

    @Test func `next up passes the rewatching and max days settings`() async throws {
        let server = HomeServer("home-nextup-options.test") { path, _ in
            switch path {
            case "/UserViews": .json(#"{"Items":[]}"#)
            case "/DisplayPreferences/default": .displayPreferences()
            case "/Shows/NextUp": .homeItems()
            default: nil
            }
        }
        let options = HomeOptions(itemsPerRow: 10, enableRewatchingNextUp: true, maxDaysNextUp: 30)

        _ = try await server.session().home(rows: [HomeRowConfig(.nextUp)], options: options)

        let sent = try #require(server.requests(to: "/Shows/NextUp").first)
        #expect(sent.query["enableRewatching"] == "true")
        #expect(sent.query["limit"] == "10")
        #expect(sent.query["nextUpDateCutoff"] != nil)
    }

    @Test func `a revoked token signs out`() async throws {
        let server = HomeServer("home-revoked.test") { path, _ in
            path == "/UserViews" ? .json(#"{"Items":[]}"#) : .unauthorized
        }

        await #expect(throws: SessionError.signedOut) {
            try await server.session().home()
        }
    }

    @Test func `an unreachable server is a connection error, not a sign-out`() async throws {
        let server = HomeServer("home-offline.test") { _, _ in nil }

        await #expect(throws: URLError.self) {
            try await server.session().home()
        }
    }
}

/// Loading each kind of row, from Wholphin's `HomeDataService`.
struct HomeRowKindTests {
    @Test func `genre cards show art from one of their items and open the genre's items`() async throws {
        let server = HomeServer("home-genres.test") { path, request in
            switch (path, request.query["genreIds"]) {
            case ("/UserViews", _): .json(HomeFixtures.views)
            case ("/Genres", _): .homeItems(#"{"Id":"g1","Name":"Comedy","Type":"Genre"}"#)
            case ("/Items", "g1"): .homeItems(#"{"Id":"m9","Name":"Film","Type":"Movie","BackdropImageTags":["bd"]}"#)
            default: nil
            }
        }

        let home = try await server.session().home(rows: [HomeRowConfig(.genres(parentID: "movies"))])

        let row = try #require(home.rows.first)
        #expect(row.title == "Genres in Movies")
        let card = try #require(row.cards.first)
        #expect(card.item.name == "Comedy")
        #expect(card.image == ItemImage(itemID: "m9", kind: .backdrop, tag: "bd"))
        var filter = LibraryFilter()
        filter.genres = ["g1"]
        let movies = Library(id: "movies", name: "Movies", kind: .movies)
        #expect(card.destination == .items(HomeItemsLink(
            title: "Comedy",
            query: LibraryQuery(library: movies, filter: filter),
        )))
        let genres = try #require(server.requests(to: "/Genres").first)
        #expect(genres.query["parentId"] == "movies")
        let art = try #require(server.requests(to: "/Items").first)
        #expect(art.query["sortBy"] == "Random")
        #expect(art.query["imageTypes"] == "Backdrop")
    }

    @Test func `a refresh keeps the genres' art and looks up only genres new since`() async throws {
        let calls = Counter()
        let server = HomeServer("home-genres-refresh.test") { path, request in
            switch (path, request.query["genreIds"]) {
            case ("/UserViews", _):
                return .json(HomeFixtures.views)
            case ("/Genres", _):
                let comedy = #"{"Id":"g1","Name":"Comedy","Type":"Genre"}"#
                let drama = #"{"Id":"g2","Name":"Drama","Type":"Genre"}"#
                return calls.next() == 1 ? .homeItems(comedy) : .homeItems(comedy, drama)
            case let ("/Items", genre?):
                return .homeItems(#"{"Id":"\#(genre)-film","Name":"Film","Type":"Movie","BackdropImageTags":["bd"]}"#)
            default:
                return nil
            }
        }
        let session = try server.session()
        let cache = HomeCache()
        let rows = [HomeRowConfig(.genres(parentID: "movies"))]

        _ = try await session.home(rows: rows, options: HomeOptions(cache: cache))
        let refreshed = try await session.home(rows: rows, options: HomeOptions(cache: cache, isRefresh: true))

        let cards = try #require(refreshed.rows.first?.cards)
        #expect(cards.map(\.image?.itemID) == ["g1-film", "g2-film"])
        #expect(server.requests(to: "/Items").compactMap { $0.query["genreIds"] } == ["g1", "g2"])
    }

    @Test func `studio cards ask for the studios of series`() async throws {
        let server = HomeServer("home-studios.test") { path, _ in
            switch path {
            case "/UserViews": .json(HomeFixtures.views)
            case "/Studios": .homeItems(#"{"Id":"st1","Name":"HBO","Type":"Studio","ImageTags":{"Thumb":"th"}}"#)
            default: nil
            }
        }

        let home = try await server.session().home(rows: [HomeRowConfig(.studios(parentID: "shows"))])

        let card = try #require(home.rows.first?.cards.first)
        #expect(card.image == ItemImage(itemID: "st1", kind: .thumb, tag: "th"))
        #expect(server.requests(to: "/Studios").first?.query["includeItemTypes"] == "Series")
    }

    @Test func `recently released asks for aired items, newest first`() {
        let parameters = JellyfinSession.recentlyReleasedParameters(userID: "u1", parentID: "movies", limit: 25)

        #expect(parameters.sortBy == [.premiereDate, .seriesSortName, .airedEpisodeOrder])
        #expect(parameters.sortOrder == [.descending, .ascending, .descending])
        #expect(parameters.isRecursive == true)
        #expect(parameters.isUnaired == false)
        #expect(parameters.maxPremiereDate != nil)
    }

    @Test func `a collection row sorts like Wholphin's and is titled by the collection`() async throws {
        func sort(_ sort: HomeRowSort?) -> String {
            let (fields, orders) = JellyfinSession.byParentSort(sort)
            return "\(fields?.map(\.rawValue) ?? []) \(orders?.map(\.rawValue) ?? [])"
        }
        #expect(sort(nil) == "[] []")
        #expect(sort(HomeRowSort(field: "SortName", direction: .descending)) == #"["SortName"] ["Descending"]"#)
        #expect(sort(HomeRowSort(field: "CriticRating"))
            == #"["CriticRating", "SortName"] ["Ascending", "Ascending"]"#)
        #expect(sort(HomeRowSort(field: "Random", direction: .descending))
            == #"["SortName", "Random"] ["Ascending", "Descending"]"#)

        let server = HomeServer("home-byparent.test") { path, _ in
            switch path {
            case "/UserViews": .json(HomeFixtures.views)
            case "/Items/c1": .json(#"{"Id":"c1","Name":"Favourites","Type":"BoxSet"}"#)
            case "/Items": .homeItems(HomeFixtures.movie())
            default: nil
            }
        }
        let row = HomeRowConfig(.byParent(parentID: "c1", recursive: true, sort: HomeRowSort(field: "CriticRating")))

        let home = try await server.session().home(rows: [row])

        #expect(home.rows.first?.title == "Favourites")
        let sent = try #require(server.requests(to: "/Items").first)
        #expect(sent.query["parentId"] == "c1")
        #expect(sent.query["recursive"] == "true")
        #expect(sent.query["sortBy"] == "CriticRating,SortName")
    }

    @Test func `a row whose parent is gone is empty, not failed`() async throws {
        let server = HomeServer("home-gone.test") { path, _ in
            switch path {
            case "/UserViews": .json(HomeFixtures.views)
            case "/Items/c1": .notFound
            case "/Items": .homeItems(HomeFixtures.movie())
            default: nil
            }
        }

        let home = try await server.session().home(rows: [
            HomeRowConfig(.byParent(parentID: "c1", recursive: false, sort: nil)),
        ])

        #expect(home.rows.isEmpty)
        #expect(home.failedRows.isEmpty)
    }

    @Test func `favourite people come from the persons endpoint, other types from items`() async throws {
        let server = HomeServer("home-favorites.test") { path, _ in
            switch path {
            case "/UserViews": .json(HomeFixtures.views)
            case "/Persons": .homeItems(#"{"Id":"p1","Name":"Ann","Type":"Person","ImageTags":{"Primary":"f"}}"#)
            case "/Items": .homeItems(HomeFixtures.movie())
            default: nil
            }
        }

        let home = try await server.session().home(rows: [
            HomeRowConfig(.favorite(itemKind: "Person")),
            HomeRowConfig(.favorite(itemKind: "Movie")),
        ])

        #expect(home.rows.map(\.title) == ["Favorite People", "Favorite Movies"])
        #expect(server.requests(to: "/Persons").first?.query["isFavorite"] == "true")
        let items = try #require(server.requests(to: "/Items").first)
        #expect(items.query["includeItemTypes"] == "Movie")
        #expect(items.query["isFavorite"] == "true")
        #expect(items.query["recursive"] == "true")
    }

    @Test func `a get items row sends its filter`() async throws {
        let server = HomeServer("home-getitems.test") { path, _ in
            switch path {
            case "/UserViews": .json(HomeFixtures.views)
            case "/Items": .homeItems(HomeFixtures.episode())
            default: nil
            }
        }
        var filter = HomeGetItemsFilter()
        filter.parentID = "1dd1c2fd-2e1b-48e4-ba94-17a2350fe9cf"
        filter.includeItemTypes = ["Episode", "NotAType"]
        filter.sortBy = ["DateCreated"]
        filter.sortOrder = ["Descending"]
        filter.isFavorite = true
        filter.years = [1999, 2000]

        let home = try await server.session().home(rows: [HomeRowConfig(.getItems(name: "Faves", filter: filter))])

        #expect(home.rows.first?.title == "Faves")
        let sent = try #require(server.requests(to: "/Items").first)
        #expect(sent.query["parentId"] == "1dd1c2fd2e1b48e4ba9417a2350fe9cf")
        #expect(sent.query["includeItemTypes"] == "Episode")
        #expect(sent.query["sortBy"] == "DateCreated")
        #expect(sent.query["sortOrder"] == "Descending")
        #expect(sent.query["isFavorite"] == "true")
        #expect(sent.query["years"] == "1999,2000")
    }

    @Test func `a get items row reads premiere dates as Wholphin writes them`() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let mayDay = try #require(calendar.date(from: DateComponents(year: 2024, month: 5, day: 1)))
        let server = HomeServer("home-getitems-dates.test") { path, _ in
            switch path {
            case "/UserViews": .json(HomeFixtures.views)
            case "/Items": .homeItems(HomeFixtures.movie())
            default: nil
            }
        }
        var filter = HomeGetItemsFilter()
        // kotlinx's LocalDateTime leaves out zero seconds.
        filter.minPremiereDate = "2024-05-01T00:00"
        filter.maxPremiereDate = "2024-05-31T23:59:59.5"

        _ = try await server.session().home(rows: [HomeRowConfig(.getItems(name: "May", filter: filter))])

        #expect(HomeGetItemsFilter.date("2024-05-01T00:00") == mayDay)
        #expect(HomeGetItemsFilter.date("2024-05-01T00:00:00") == mayDay)
        #expect(HomeGetItemsFilter.date("2024-05-01T00:00:00Z") == Date(timeIntervalSince1970: 1_714_521_600))
        #expect(HomeGetItemsFilter.date("May 1") == nil)
        let sent = try #require(server.requests(to: "/Items").first)
        #expect(sent.query["minPremiereDate"] != nil)
        #expect(sent.query["maxPremiereDate"] != nil)
    }

    @Test func `a custom endpoint gets the user, query and headers, and must be on the server`() async throws {
        let server = HomeServer("home-custom.test") { path, _ in
            switch path {
            case "/UserViews": .json(HomeFixtures.views)
            case "/HomeScreen/Section": .homeItems(HomeFixtures.movie())
            default: nil
            }
        }
        let endpoint = HomeCustomEndpoint(
            endpoint: "/HomeScreen/Section?kind=latest",
            title: "Picks",
            headers: [KeyValueEntry(key: "X-Test", value: "1")],
            query: [KeyValueEntry(key: "Section", value: "Latest")],
        )
        let session = try server.session()

        let home = try await session.home(rows: [HomeRowConfig(.customEndpoint(endpoint))])

        #expect(home.rows.first?.title == "Picks")
        let sent = try #require(server.requests(to: "/HomeScreen/Section").first)
        #expect(sent.query == ["kind": "latest", "userId": "u1", "Section": "Latest"])
        let elsewhere = HomeCustomEndpoint(endpoint: "https://elsewhere.test/items", title: "No")
        await #expect(throws: HomeRowError.endpointNotOnServer) {
            try await session.customEndpointItems(elsewhere)
        }
    }

    @Test func `live TV rows come from the Live TV source`() async throws {
        let server = HomeServer("home-livetv.test") { path, _ in
            path == "/UserViews" ? .json(HomeFixtures.views) : nil
        }
        let options = HomeOptions(liveTV: FakeLiveTV())

        let home = try await server.session().home(
            rows: [HomeRowConfig(.tvChannels), HomeRowConfig(.tvPrograms), HomeRowConfig(.recordings)],
            options: options,
        )

        #expect(home.rows.map(\.title) == ["Channels", "Watch Live", "Active Recordings"])
        #expect(home.rows.map { $0.items.first?.name } == ["channel", "program", "recording"])
    }

    @Test func `suggestions mix picks and keep them between loads`() async throws {
        let server = HomeServer("home-suggestions.test") { path, request in
            switch (path, request.query["sortBy"], request.query["ids"]) {
            case ("/UserViews", _, _): .json(HomeFixtures.views)
            case ("/Items", "DatePlayed", _):
                .homeItems(#"{"Id":"w1","Type":"Movie","GenreItems":[{"Id":"g1","Name":"Drama"}]}"#)
            case ("/Items", "Random", _), ("/Items", "DateCreated", _):
                .homeItems(#"{"Id":"w1","Type":"Movie"}"#, #"{"Id":"s1","Type":"Movie"}"#)
            case ("/Items", _, .some):
                .homeItems(#"{"Id":"s1","Name":"Pick","Type":"Movie"}"#)
            default: nil
            }
        }
        let session = try server.session()
        let options = HomeOptions(cache: HomeCache())
        let row = HomeRowConfig(.suggestions(parentID: "movies"))

        let first = try await session.home(rows: [row], options: options)
        let second = try await session.home(rows: [row], options: options)

        #expect(first.rows.first?.title == "Suggestions for Movies")
        // What was watched isn't suggested.
        #expect(first.rows.first?.items.map(\.id) == ["s1"])
        #expect(second.rows == first.rows)
        let history = server.requests(to: "/Items").filter { $0.query["sortBy"] == "DatePlayed" }
        #expect(history.count == 1)
        let byGenre = server.requests(to: "/Items").first { $0.query["genreIds"] != nil }
        #expect(byGenre?.query["genreIds"] == "g1")
        #expect(byGenre?.query["excludeItemIds"] == "w1")
    }

    @Test func `suggestions are only for movie and TV libraries`() async throws {
        let server = HomeServer("home-suggestions-music.test") { path, _ in
            path == "/UserViews" ? .json(#"{"Items":[{"Id":"mu","Name":"Music","CollectionType":"music"}]}"#) : nil
        }

        let home = try await server.session().home(rows: [HomeRowConfig(.suggestions(parentID: "mu"))])

        #expect(home.failedRows == ["suggestions.mu"])
    }
}

private struct FakeLiveTV: HomeLiveTVSource {
    func recordingsInProgress(limit _: Int) async throws -> [MediaItem] {
        [MediaItem(id: "r1", name: "recording", kind: .video)]
    }

    func programsOnNow(limit _: Int) async throws -> [MediaItem] {
        [MediaItem(id: "p1", name: "program", kind: .other)]
    }

    func channels(limit _: Int) async throws -> [MediaItem] {
        [MediaItem(id: "c1", name: "channel", kind: .other)]
    }
}

/// Counts the requests a mock server answers.
private final class Counter: Sendable {
    private let value = Mutex(0)

    func next() -> Int {
        value.withLock { count in
            count += 1
            return count
        }
    }
}
