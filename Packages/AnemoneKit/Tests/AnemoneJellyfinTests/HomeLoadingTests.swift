import AnemoneCore
@testable import AnemoneJellyfin
import Foundation
import Synchronization
import Testing

/// What loading and refreshing Home reads, keeps between loads, and asks for again.
struct HomeLoadingTests {
    @Test func `a load reads Anemone's entry once, and asks about the plugin once a session`() async throws {
        let removed = #"{"value":{"s9":"2026-10-25T10:00:00.000"}}"#
        let server = HomeServer("settings-once.test") { path, _ in
            switch path {
            case "/DisplayPreferences/default": .displayPreferences(["removeNextUp": removed])
            case "/UserViews": .json(HomeFixtures.views)
            case "/Shows/NextUp": .homeItems(HomeFixtures.episode("e1", series: "s9"), HomeFixtures.episode("e2"))
            default: .notFound
            }
        }
        let session = try server.session()
        let cache = HomeCache()

        let resolution = try await session.resolveHomeSettings(cache: cache)
        let home = try await session.home(
            rows: [HomeRowConfig(.nextUp)],
            removedFromNextUp: resolution.removedFromNextUp,
            options: HomeOptions(cache: cache),
        )
        _ = try await session.resolveHomeSettings(cache: cache)

        #expect(resolution.source == .default)
        #expect(home.rows.first?.items.map(\.id) == ["e2"])
        #expect(server.requests(to: "/DisplayPreferences/default").count == 2)
        #expect(server.requests(to: "/wholphin/public").count == 1)
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
