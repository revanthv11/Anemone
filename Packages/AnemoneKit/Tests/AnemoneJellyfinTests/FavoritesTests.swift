import AnemoneJellyfin
import Foundation
import Synchronization
import Testing

/// The Favorites page's queries, after Wholphin's `FavoritesViewModel`.
struct FavoritesTests {
    private func session(host: String) throws -> JellyfinSession {
        try JellyfinSession(
            serverURL: #require(URL(string: "https://\(host)")),
            userID: "u1",
            accessToken: "tok",
            identity: ClientIdentity(deviceName: "Test TV", deviceID: "device-1", appVersion: "0.1.0"),
            sessionConfiguration: { MockServer.sessionConfiguration() },
        )
    }

    @Test func `asks only for the types the libraries can hold, in Wholphin's order`() {
        let libraries = [
            Library(id: "l2", name: "Music", kind: .music),
            Library(id: "l1", name: "Movies", kind: .movies),
            Library(id: "l3", name: "Shows", kind: .shows),
        ]

        #expect(FavoritesSection.kinds(for: libraries) == [.movie, .series, .episode, .person, .musicAlbum, .audio])
        #expect(FavoritesSection.kinds(for: []) == [.person])
    }

    @Test func `asks for a type's favourites by name, with what cards and the header show`() async throws {
        let sent = Recorder()
        MockServer.register(host: "favorite-movies.test") { request in
            guard request.url?.path() == "/Items" else { return nil }
            sent.last.withLock { $0 = SentRequest(request) }
            return .json(
                #"{"Items":[{"Id":"m1","Name":"Film","Type":"Movie","UserData":{"Key":"m1","IsFavorite":true}}]}"#,
            )
        }

        let items = try await session(host: "favorite-movies.test").favorites(of: .movie)

        #expect(items.map(\.id) == ["m1"])
        #expect(items.first?.userState.isFavorite == true)
        let query = try #require(sent.request?.query)
        #expect(query["includeItemTypes"] == "Movie")
        #expect(query["isFavorite"] == "true")
        #expect(query["recursive"] == "true")
        #expect(query["sortBy"] == "SortName")
        #expect(query["sortOrder"] == "Ascending")
        #expect(query["limit"] == "100")
        #expect(query["fields"] == "Overview,PrimaryImageAspectRatio,ChildCount")
        #expect(query["userId"] == "u1")
    }

    @Test func `asks for favourite people through Persons`() async throws {
        let sent = Recorder()
        MockServer.register(host: "favorite-people.test") { request in
            guard request.url?.path() == "/Persons" else { return nil }
            sent.last.withLock { $0 = SentRequest(request) }
            return .json(#"{"Items":[{"Id":"p1","Name":"Actor","Type":"Person"}]}"#)
        }

        let people = try await session(host: "favorite-people.test").favorites(of: .person)

        #expect(people.map(\.item.kind) == [.person])
        #expect(sent.request?.query["isFavorite"] == "true")
        #expect(sent.request?.query["userId"] == "u1")
    }

    @Test func `leaves out empty rows and names the ones that failed`() async throws {
        MockServer.register(host: "favorite-rows.test") { request in
            let type = request.url?.queryValues["includeItemTypes"]
            switch (request.url?.path(), type) {
            case ("/Items", "Movie"):
                return .json(#"{"Items":[{"Id":"m1","Name":"Film","Type":"Movie"}]}"#)
            case ("/Items", "Series"):
                return MockServer.Reply(status: 500, body: "")
            case ("/Items", _), ("/Persons", _):
                return .json(#"{"Items":[]}"#)
            default:
                return nil
            }
        }
        let libraries = [Library(id: "l1", name: "Movies", kind: .movies), Library(id: "l2", name: "TV", kind: .shows)]

        let content = try await session(host: "favorite-rows.test").favorites(for: libraries)

        #expect(content.sections.map(\.kind) == [.movie])
        #expect(content.failedKinds == [.series])
    }

    @Test func `fails when every row fails, and reports a revoked token`() async throws {
        MockServer.register(host: "favorite-down.test") { _ in MockServer.Reply(status: 500, body: "") }
        MockServer.register(host: "favorite-revoked.test") { request in
            request.url?.path() == "/Persons" ? .unauthorized : .json(#"{"Items":[]}"#)
        }
        let libraries = [Library(id: "l1", name: "Movies", kind: .movies)]

        await #expect(throws: (any Error).self) {
            try await session(host: "favorite-down.test").favorites(for: libraries)
        }
        await #expect(throws: SessionError.signedOut) {
            try await session(host: "favorite-revoked.test").favorites(for: libraries)
        }
    }

    @Test func `a row loaded again after a change replaces its old one, in the page's order`() {
        func favorite(_ id: String, _ kind: MediaItem.Kind) -> ItemDetails {
            ItemDetails(item: MediaItem(id: id, name: id, kind: kind))
        }
        let page = FavoritesContent(
            sections: [
                FavoritesSection(kind: .movie, items: [favorite("m1", .movie)]),
                FavoritesSection(kind: .musicAlbum, items: [favorite("a1", .musicAlbum)]),
            ],
            failedKinds: [.series],
        )

        let added = page.replacing(.series, with: [favorite("s1", .series)])
        let removed = page.replacing(.movie, with: [])
        let changed = page.replacing(.musicAlbum, with: [favorite("a1", .musicAlbum), favorite("a2", .musicAlbum)])

        #expect(added.sections.map(\.kind) == [.movie, .series, .musicAlbum])
        #expect(added.failedKinds.isEmpty)
        #expect(removed.sections.map(\.kind) == [.musicAlbum])
        #expect(removed.failedKinds == [.series])
        #expect(changed.sections.last?.items.map(\.id) == ["a1", "a2"])
    }
}
