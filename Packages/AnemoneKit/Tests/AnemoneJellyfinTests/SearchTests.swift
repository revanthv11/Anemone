import AnemoneJellyfin
import Foundation
import Synchronization
import Testing

/// Search queries against the fake server, result ranking, the kinds offered for a set of
/// libraries, and recent searches.
struct SearchTests {
    // MARK: Requests

    @Test func `searches one kind of item with Wholphin's query`() async throws {
        let sent = register(host: "search-movies.test", path: "/Items", reply: .items(
            #"{"Id":"m1","Name":"The Great Train Robbery","Type":"Movie","ProductionYear":1903}"#,
            #"{"Id":"m2","Name":"Robbery","Type":"Movie","UserData":{"Key":"m2","IsFavorite":true,"Played":true}}"#,
        ))

        let results = try await session(host: "search-movies.test").search("robbery", for: .movie)

        let query = try #require(sent.request?.query)
        #expect(sent.request?.method == "GET")
        #expect(query["searchTerm"] == "robbery")
        #expect(query["includeItemTypes"] == "Movie")
        #expect(query["recursive"] == "true")
        #expect(query["limit"] == "50")
        #expect(query["enableTotalRecordCount"] == "false")
        #expect(query["enableUserData"] == "true")
        #expect(query["userId"] == "u1")
        #expect(query["fields"] == "Overview,PrimaryImageAspectRatio,ChildCount")
        // The exact match moves ahead of the server's first result.
        #expect(results.map(\.id) == ["m2", "m1"])
        #expect(results.first?.userState.isFavorite == true)
        #expect(results.last?.item.year == 1903)
    }

    @Test func `people come from the persons endpoint`() async throws {
        let sent = register(host: "search-people.test", path: "/Persons", reply: .items(
            #"{"Id":"p1","Name":"Bela Lugosi","Type":"Person","ImageTags":{"Primary":"face"}}"#,
        ))

        let people = try await session(host: "search-people.test").search("bela", for: .person)

        let query = try #require(sent.request?.query)
        #expect(query["searchTerm"] == "bela")
        #expect(query["limit"] == "50")
        #expect(query["userId"] == "u1")
        #expect(query["includeItemTypes"] == nil)
        #expect(people.map(\.item.kind) == [.person])
        #expect(people.first?.ownPrimaryImage == ItemImage(itemID: "p1", kind: .primary, tag: "face"))
    }

    @Test func `music artists come from the artists endpoint`() async throws {
        let sent = register(host: "search-artists.test", path: "/Artists", reply: .items(
            #"{"Id":"a1","Name":"Binaerpilot","Type":"MusicArtist"}"#,
        ))

        let artists = try await session(host: "search-artists.test").search("binaer", for: .musicArtist, limit: 20)

        let query = try #require(sent.request?.query)
        #expect(query["searchTerm"] == "binaer")
        #expect(query["limit"] == "20")
        #expect(query["enableTotalRecordCount"] == "false")
        #expect(artists.map(\.id) == ["a1"])
    }

    @Test func `combined results ask for every kind in one query`() async throws {
        let sent = register(host: "search-combined.test", path: "/Items", reply: .items(
            #"{"Id":"e1","Name":"Night","Type":"Episode","SeriesName":"Show"}"#,
            #"{"Id":"s1","Name":"Night","Type":"Series"}"#,
            #"{"Id":"m1","Name":"Night","Type":"Movie"}"#,
        ))

        let results = try await session(host: "search-combined.test")
            .search("night", forAll: [.movie, .series, .episode])

        #expect(sent.request?.query["includeItemTypes"] == "Movie,Series,Episode")
        #expect(sent.request?.query["searchTerm"] == "night")
        // Equal names: series, then movies, then episodes.
        #expect(results.map(\.id) == ["s1", "m1", "e1"])
    }

    @Test func `combined results with no kinds ask for nothing`() async throws {
        let sent = register(host: "search-no-kinds.test", path: "/Items", reply: .items(
            #"{"Id":"m1","Name":"Night","Type":"Movie"}"#,
        ))

        let results = try await session(host: "search-no-kinds.test").search("night", forAll: [])

        #expect(sent.request == nil)
        #expect(results.isEmpty)
    }

    @Test func `suggestions for a kind are the items with the newest content`() async throws {
        let sent = register(host: "search-latest.test", path: "/Items", reply: .items(
            #"{"Id":"c1","Name":"Box","Type":"BoxSet","ChildCount":3}"#,
        ))

        let latest = try await session(host: "search-latest.test").latestItems(of: .collection)

        let query = try #require(sent.request?.query)
        #expect(query["includeItemTypes"] == "BoxSet")
        #expect(query["sortBy"] == "DateLastContentAdded")
        #expect(query["sortOrder"] == "Descending")
        #expect(query["limit"] == "25")
        #expect(query["searchTerm"] == nil)
        #expect(latest.first?.childCount == 3)
    }

    @Test func `a revoked token signs the user out`() async throws {
        MockServer.register(host: "search-revoked.test") { _ in .unauthorized }

        await #expect(throws: SessionError.signedOut) {
            try await session(host: "search-revoked.test").search("x", for: .series)
        }
    }

    // MARK: Relevance

    @Test(arguments: [
        ("dracula", 1),
        ("dracula's daughter", 101),
        ("son of dracula", 201),
        ("draculas", 101),
        ("eldracula", 301),
        ("dracola", 351),
        ("dracu", 376),
        ("frankenstein", 401),
    ])
    func `scores movies by how their name matches`(name: String, score: Int) {
        #expect(SearchRelevance.score(name: name, kind: .movie, query: "Dracula") == score)
    }

    @Test func `scores by kind within a band`() {
        let scores = [MediaItem.Kind.series, .movie, .collection, .person, .episode].map { kind in
            SearchRelevance.score(name: "Night", kind: kind, query: "night")
        }

        #expect(scores == [0, 1, 2, 5, 10])
        #expect(SearchRelevance.score(name: nil, kind: .movie, query: "night") == Int.max)
    }

    @Test func `a slashed query matches as a regular expression`() {
        #expect(SearchRelevance.score(name: "King Lear", kind: .movie, query: "/^k.*r$/") == 251)
        #expect(SearchRelevance.score(name: "King Lear", kind: .movie, query: "/^Q/") == 401)
        // Names are matched in lower case, so only the flag lets an upper-case pattern match.
        #expect(SearchRelevance.score(name: "King Lear", kind: .movie, query: "/LEAR/") == 401)
        #expect(SearchRelevance.score(name: "King Lear", kind: .movie, query: "/LEAR/i") == 251)
        #expect(SearchRelevance.score(name: "King Lear", kind: .movie, query: "/[/") == 401)
    }

    @Test func `sorts by a regular expression`() {
        let items = ["Queen Lear", "King Lear", "Lear King"].enumerated().map { index, name in
            ItemDetails(item: MediaItem(id: "m\(index)", name: name, kind: .movie))
        }

        #expect(SearchRelevance.sorted(items, for: "/^k/").map(\.item.name) == ["King Lear", "Queen Lear", "Lear King"])
        // A pattern that doesn't compile matches nothing, so the server's order stays.
        #expect(SearchRelevance.sorted(items, for: "/[/").map(\.item.name) == ["Queen Lear", "King Lear", "Lear King"])
    }

    // MARK: Kinds

    @Test func `offers people and the kinds the libraries hold, in Wholphin's order`() {
        let libraries = [
            Library(id: "l1", name: "Music", kind: .music),
            Library(id: "l2", name: "Movies", kind: .movies),
            Library(id: "l3", name: "Shows", kind: .shows),
        ]

        #expect(SearchKind.searchable(in: libraries) == [
            .movie, .series, .episode, .person, .musicAlbum, .musicArtist, .audio,
        ])
        #expect(SearchKind.searchable(in: libraries, excluding: [.person, .episode]) == [
            .movie, .series, .musicAlbum, .musicArtist, .audio,
        ])
        #expect(SearchKind.searchable(in: []) == [.person])
    }

    @Test func `home videos hold videos and photos, and mixed libraries hold films and shows`() {
        #expect(Library(id: "h", name: "Home", kind: .homeVideos).searchKinds == [.video, .photo, .photoAlbum])
        #expect(Library(id: "m", name: "Mixed", kind: .mixed).searchKinds == [.movie, .series, .episode, .video])
        #expect(Library(id: "t", name: "Live", kind: .liveTV).searchKinds.isEmpty)
    }

    // MARK: Recent searches

    @Test func `recent searches put the newest first without repeats`() {
        var recent = RecentSearches()
        recent.add("dracula")
        recent.add("  King Lear ")
        recent.add("")
        recent.add("Dracula")

        #expect(recent.terms == ["Dracula", "King Lear"])

        recent.remove("king lear")
        #expect(recent.terms == ["Dracula"])
        recent.clear()
        #expect(recent.terms.isEmpty)
    }

    @Test func `recent searches keep the last ten`() {
        var recent = RecentSearches()
        for number in 1 ... 12 {
            recent.add("search \(number)")
        }

        #expect(recent.terms.count == RecentSearches.limit)
        #expect(recent.terms.first == "search 12")
        #expect(recent.terms.last == "search 3")
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

    /// Answers requests for `path` with `reply`, recording the last one.
    private func register(host: String, path: String, reply: MockServer.Reply) -> Recorder {
        let recorder = Recorder()
        MockServer.register(host: host) { request in
            guard request.url?.path() == path else { return nil }
            recorder.last.withLock { $0 = SentRequest(request) }
            return reply
        }
        return recorder
    }
}

private extension MockServer.Reply {
    static func items(_ items: String...) -> Self {
        .json(#"{"Items":[\#(items.joined(separator: ","))]}"#)
    }
}
