import AnemoneJellyfin
import Foundation
import Synchronization
import Testing

struct JellyfinSessionTests {
    private func session(host: String) throws -> JellyfinSession {
        try JellyfinSession(
            serverURL: #require(URL(string: "https://\(host)")),
            userID: "u1",
            accessToken: "tok",
            identity: ClientIdentity(deviceName: "Test TV", deviceID: "device-1", appVersion: "0.1.0"),
            sessionConfiguration: MockServer.sessionConfiguration(),
        )
    }

    @Test func `lists supported libraries in the server's order`() async throws {
        let query = Mutex<[String: String]>([:])
        MockServer.register(host: "views.test") { request in
            guard request.url?.path() == "/UserViews" else { return nil }
            query.withLock { $0 = request.query }
            return .json(#"""
            {"Items":[
              {"Id":"l1","Name":"Movies","CollectionType":"movies"},
              {"Id":"l2","Name":"Books","CollectionType":"books"},
              {"Id":"l3","Name":"Shows","CollectionType":"tvshows"},
              {"Id":"l4","Name":"Everything"}
            ]}
            """#)
        }

        let libraries = try await session(host: "views.test").libraries()

        #expect(libraries == [
            Library(id: "l1", name: "Movies", kind: .movies),
            Library(id: "l3", name: "Shows", kind: .shows),
            Library(id: "l4", name: "Everything", kind: .mixed),
        ])
        #expect(query.withLock { $0["userId"] } == "u1")
    }

    @Test func `maps continue watching items`() async throws {
        let query = Mutex<[String: String]>([:])
        MockServer.register(host: "resume.test") { request in
            guard request.url?.path() == "/UserItems/Resume" else { return nil }
            query.withLock { $0 = request.query }
            return .items(Self.movieJSON, Self.episodeJSON)
        }

        let items = try await session(host: "resume.test").continueWatching(limit: 25)

        #expect(items == [Self.movie, Self.episode])
        let sent = query.withLock { $0 }
        #expect(sent["mediaTypes"] == "Video")
        #expect(sent["limit"] == "25")
        #expect(sent["fields"] == "Overview")
    }

    @Test func `next up leaves partly watched episodes to continue watching`() async throws {
        let query = Mutex<[String: String]>([:])
        MockServer.register(host: "nextup.test") { request in
            guard request.url?.path() == "/Shows/NextUp" else { return nil }
            query.withLock { $0 = request.query }
            return .items(Self.episodeJSON)
        }

        let items = try await session(host: "nextup.test").nextUp(limit: 25)

        #expect(items == [Self.episode])
        let sent = query.withLock { $0 }
        #expect(sent["enableResumable"] == "false")
        #expect(sent["enableRewatching"] == "false")
    }

    @Test func `recently added shows new episodes as their series`() async throws {
        let query = Mutex<[String: String]>([:])
        MockServer.register(host: "latest.test") { request in
            guard request.url?.path() == "/Items/Latest" else { return nil }
            query.withLock { $0 = request.query }
            return .json("""
            [\(Self.episodeJSON),
             {"Id":"s2","Name":"Grouped Show","Type":"Series","ChildCount":3,"ImageTags":{"Primary":"g"}},
             \(Self.episodeJSON)]
            """)
        }

        let items = try await session(host: "latest.test").recentlyAdded(in: "l3", limit: 25)

        #expect(items.map(\.id) == ["series", "s2"])
        #expect(items.first?.posterImage == ItemImage(itemID: "series", kind: .primary, tag: "sp"))
        let sent = query.withLock { $0 }
        #expect(sent["parentId"] == "l3")
        #expect(sent["groupItems"] == "true")
    }

    @Test func `home hides empty rows and keeps the rows that loaded`() async throws {
        let requested = Mutex<[String]>([])
        MockServer.register(host: "home.test") { request in
            let parentID = request.query["parentId"]
            requested.withLock { $0.append(parentID ?? request.url?.path() ?? "") }
            switch (request.url?.path(), parentID) {
            case ("/UserViews", _):
                return .json(#"""
                {"Items":[
                  {"Id":"movies","Name":"Movies","CollectionType":"movies"},
                  {"Id":"shows","Name":"Shows","CollectionType":"tvshows"},
                  {"Id":"live","Name":"Live TV","CollectionType":"livetv"}
                ]}
                """#)
            case ("/UserItems/Resume", _):
                return .items(Self.movieJSON)
            case ("/Shows/NextUp", _):
                return .items()
            case ("/Items/Latest", "movies"):
                return MockServer.Reply(status: 500, body: "")
            case ("/Items/Latest", "shows"):
                return .json("[\(Self.episodeJSON)]")
            default:
                return nil
            }
        }

        let home = try await session(host: "home.test").home()

        let shows = Library(id: "shows", name: "Shows", kind: .shows)
        #expect(home.rows.map(\.kind) == [.continueWatching, .recentlyAdded(shows)])
        #expect(home.failedRows == [.recentlyAdded(Library(id: "movies", name: "Movies", kind: .movies))])
        #expect(home.libraries.map(\.id) == ["movies", "shows", "live"])
        #expect(!requested.withLock { $0.contains("live") })
    }

    @Test func `home reports a revoked token as signed out`() async throws {
        MockServer.register(host: "revoked.test") { request in
            request.url?.path() == "/UserViews" ? .json(#"{"Items":[]}"#) : .unauthorized
        }

        await #expect(throws: SessionError.signedOut) {
            try await session(host: "revoked.test").home()
        }
    }

    @Test func `home fails when the server can't be reached`() async throws {
        MockServer.register(host: "offline.test") { _ in nil }

        await #expect(throws: (any Error).self) {
            try await session(host: "offline.test").home()
        }
    }

    // MARK: Fixtures

    private static let movieJSON = #"""
    {"Id":"m1","Name":"Film","Type":"Movie","ProductionYear":2024,"Overview":"A film.",
     "RunTimeTicks":72000000000,"OfficialRating":"PG-13",
     "ImageTags":{"Primary":"p","Thumb":"t"},"BackdropImageTags":["b"],
     "UserData":{"Key":"m1","PlayedPercentage":42.5}}
    """#

    private static let movie = MediaItem(
        id: "m1",
        name: "Film",
        kind: .movie,
        year: 2024,
        overview: "A film.",
        runtime: .seconds(7200),
        officialRating: "PG-13",
        progress: 0.425,
        artwork: .init(primaryTag: "p", thumbTag: "t", backdropTag: "b"),
    )

    private static let episodeJSON = #"""
    {"Id":"e1","Name":"Pilot","Type":"Episode","SeriesId":"series","SeriesName":"Show",
     "ParentIndexNumber":1,"IndexNumber":3,"ImageTags":{"Primary":"still"},
     "SeriesPrimaryImageTag":"sp","ParentThumbItemId":"series","ParentThumbImageTag":"st",
     "ParentBackdropItemId":"series","ParentBackdropImageTags":["sb"],
     "UserData":{"Key":"e1","PlayedPercentage":0}}
    """#

    private static let episode = MediaItem(
        id: "e1",
        name: "Pilot",
        kind: .episode,
        episode: .init(seriesID: "series", seriesName: "Show", seasonNumber: 1, episodeNumber: 3),
        artwork: .init(
            primaryTag: "still",
            seriesPrimary: ItemImage(itemID: "series", kind: .primary, tag: "sp"),
            parentThumb: ItemImage(itemID: "series", kind: .thumb, tag: "st"),
            parentBackdrop: ItemImage(itemID: "series", kind: .backdrop, tag: "sb"),
        ),
    )
}

private extension URLRequest {
    var query: [String: String] {
        let items = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }) { first, _ in first }
    }
}

private extension MockServer.Reply {
    static func items(_ items: String...) -> Self {
        .json(#"{"Items":[\#(items.joined(separator: ","))]}"#)
    }
}
