@testable import AnemoneJellyfin
import Foundation
import Synchronization
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

    @Test func `next up keeps only episodes of a series`() async throws {
        // As Wholphin's `getPotentialItems`, which drops next up items without a series ID.
        let orphan = #"{"Id":"e9","Name":"Episode e9","Type":"Episode","IndexNumber":1,"UserData":{"Key":"e9"}}"#
        let server = HomeServer("topshelf-noseries.test") { path, _ in
            switch path {
            case "/DisplayPreferences/default": .displayPreferences()
            case "/UserItems/Resume": .homeItems()
            case "/Shows/NextUp": .homeItems(orphan, HomeFixtures.episode("e1", series: "s1"))
            default: nil
            }
        }

        let rows = try await server.session().topShelfRows()

        #expect(rows.first?.items.map(\.id) == ["e1"])
    }

    @Test func `next up doesn't wait for the series taken out of it`() async throws {
        let session = try JellyfinSession(
            serverURL: #require(URL(string: "https://topshelf-parallel.test")),
            userID: "u1",
            accessToken: "tok",
            identity: ClientIdentity(deviceName: "Test TV", deviceID: "device-1", appVersion: "0.1.0"),
            sessionConfiguration: {
                let configuration = URLSessionConfiguration.ephemeral
                configuration.protocolClasses = [PrefsAfterNextUp.self]
                return configuration
            },
        )

        let rows = try await session.topShelfRows()

        // The DisplayPreferences read was answered only once Next Up had been asked for; a Next
        // Up request that waited for it would have timed it out, showing the removed series.
        #expect(!PrefsAfterNextUp.timedOut)
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

/// A Top Shelf server that holds back its DisplayPreferences reply, with series s2 taken out of
/// Next Up, until Next Up has been asked for, or 5 s have passed. `MockServer`'s handlers answer
/// at once, on the one thread URL loading gives every fake server, so blocking one would block
/// Next Up's request too.
private final class PrefsAfterNextUp: URLProtocol, @unchecked Sendable {
    private struct State {
        var heldPrefs: PrefsAfterNextUp?
        var isNextUpAsked = false
        var timedOut = false
    }

    private static let state = Mutex(State())

    static var timedOut: Bool {
        state.withLock(\.timedOut)
    }

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        switch request.url?.path() {
        case "/DisplayPreferences/default":
            let isNextUpAsked = Self.state.withLock { state in
                if !state.isNextUpAsked {
                    state.heldPrefs = self
                }
                return state.isNextUpAsked
            }
            guard !isNextUpAsked else { return answerPrefs() }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [self] in
                let isHeld = Self.state.withLock { state in
                    guard state.heldPrefs === self else { return false }
                    state.heldPrefs = nil
                    state.timedOut = true
                    return true
                }
                if isHeld {
                    answer(.notFound)
                }
            }
        case "/Shows/NextUp":
            answer(.homeItems(HomeFixtures.episode("e1", series: "s1"), HomeFixtures.episode("e2", series: "s2")))
            let held = Self.state.withLock { state in
                state.isNextUpAsked = true
                defer { state.heldPrefs = nil }
                return state.heldPrefs
            }
            held?.answerPrefs()
        default:
            answer(.homeItems())
        }
    }

    override func stopLoading() {}

    private func answerPrefs() {
        let removed = (try? RemovedFromNextUp(dates: ["s2": Date.now - 86400]).json()) ?? ""
        answer(.displayPreferences(["removeNextUp": removed]))
    }

    private func answer(_ reply: MockServer.Reply) {
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: reply.status,
                  httpVersion: nil,
                  headerFields: ["Content-Type": "application/json"],
              )
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
