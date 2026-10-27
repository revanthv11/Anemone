@testable import AnemoneJellyfin
import Foundation
import Testing

struct TopShelfTests {
    @Test func `shows continue watching, then next up without the series in progress`() async throws {
        let server = HomeServer("topshelf-rows.test") { path, _ in
            switch path {
            case "/DisplayPreferences/default": .displayPreferences()
            case "/UserItems/Resume":
                .homeItems(HomeFixtures.movie("m1"), HomeFixtures.episode("e1", series: "s1"))
            case "/Shows/NextUp":
                .homeItems(HomeFixtures.episode("e2", series: "s1"), HomeFixtures.episode("e3", series: "s2"))
            default: nil
            }
        }

        let rows = try await server.session().topShelfRows()

        #expect(rows.map(\.kind) == [.continueWatching, .nextUp])
        #expect(rows.map(\.title) == ["Continue Watching", "Next Up"])
        #expect(rows[0].items.map(\.id) == ["m1", "e1"])
        // Wholphin's Watch Next row leaves out next episodes of series already in progress.
        #expect(rows[1].items.map(\.id) == ["e3"])
        // Read-only, and nothing but the two rows and the removed series.
        #expect(Set(server.paths) == ["/DisplayPreferences/default", "/UserItems/Resume", "/Shows/NextUp"])
    }

    @Test func `asks for ten of each, with the next up settings`() async throws {
        let server = HomeServer("topshelf-options.test") { path, _ in
            switch path {
            case "/DisplayPreferences/default": .displayPreferences()
            case "/UserItems/Resume", "/Shows/NextUp": .homeItems()
            default: nil
            }
        }
        let options = TopShelfOptions(enableRewatchingNextUp: true, maxDaysNextUp: 30)

        let rows = try await server.session().topShelfRows(options: options)

        #expect(rows.isEmpty)
        let resume = try #require(server.requests(to: "/UserItems/Resume").first)
        #expect(resume.method == "GET")
        #expect(resume.query["limit"] == "10")
        #expect(resume.query["mediaTypes"] == "Video")
        let nextUp = try #require(server.requests(to: "/Shows/NextUp").first)
        #expect(nextUp.method == "GET")
        #expect(nextUp.query["limit"] == "10")
        #expect(nextUp.query["enableResumable"] == "false")
        #expect(nextUp.query["enableRewatching"] == "true")
        #expect(nextUp.query["nextUpDateCutoff"] != nil)
    }

    @Test func `leaves out series taken out of next up`() async throws {
        let removedJSON = try RemovedFromNextUp(dates: ["s2": Date.now - 86400]).json()
        let server = HomeServer("topshelf-removed.test") { path, _ in
            switch path {
            case "/DisplayPreferences/default": .displayPreferences(["removeNextUp": removedJSON])
            case "/UserItems/Resume": .homeItems()
            case "/Shows/NextUp":
                .homeItems(HomeFixtures.episode("e1", series: "s1"), HomeFixtures.episode("e2", series: "s2"))
            default: nil
            }
        }

        let rows = try await server.session().topShelfRows()

        #expect(rows.map(\.kind) == [.nextUp])
        #expect(rows.first?.items.map(\.id) == ["e1"])
    }

    @Test func `shows every series when the removed list can't be read`() async throws {
        let server = HomeServer("topshelf-noprefs.test") { path, _ in
            switch path {
            case "/DisplayPreferences/default": MockServer.Reply(status: 500, body: "")
            case "/UserItems/Resume": .homeItems()
            case "/Shows/NextUp": .homeItems(HomeFixtures.episode("e1", series: "s1"))
            default: nil
            }
        }

        let rows = try await server.session().topShelfRows()

        #expect(rows.first?.items.map(\.id) == ["e1"])
    }

    @Test func `the app leaves its next up settings for the Top Shelf`() throws {
        let defaults = try #require(UserDefaults(suiteName: "topshelf-\(UUID().uuidString)"))
        #expect(TopShelfOptions(defaults: defaults) == TopShelfOptions())

        TopShelfOptions(limit: 3, enableRewatchingNextUp: true, maxDaysNextUp: 30).write(to: defaults)

        #expect(TopShelfOptions(defaults: defaults)
            == TopShelfOptions(enableRewatchingNextUp: true, maxDaysNextUp: 30))
    }

    @Test func `a revoked token signs out`() async throws {
        let server = HomeServer("topshelf-revoked.test") { _, _ in .unauthorized }

        await #expect(throws: SessionError.signedOut) {
            try await server.session().topShelfRows()
        }
    }
}
