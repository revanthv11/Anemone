import AnemoneJellyfin
import Foundation
import Testing

/// What Play and Shuffle on a collection ask the server for, and the queue they make.
struct CollectionQueuesTests {
    private static let videoTypes = "Movie,Episode,Video,MusicVideo"

    private func session(host: String) throws -> JellyfinSession {
        try JellyfinSession(
            serverURL: #require(URL(string: "https://\(host)")),
            userID: "u1",
            accessToken: "tok",
            identity: ClientIdentity(deviceName: "Test TV", deviceID: "device-1", appVersion: "0.1.0"),
            sessionConfiguration: { MockServer.sessionConfiguration() },
        )
    }

    /// Answers `/Items` with `reply`, recording every request.
    private func register(host: String, reply: @escaping @Sendable (SentRequest) -> String?) -> Recorder {
        let recorder = Recorder()
        MockServer.register(host: host) { request in
            guard request.url?.path() == "/Items" else { return nil }
            return reply(recorder.record(request)).map { .json($0) }
        }
        return recorder
    }

    @Test func `in its own order, a collection plays what its page lists and counts the rest`() async throws {
        let page = Self.items([Self.movie("m1"), Self.episode("e1"), Self.song("a1")])
        let recorder = register(host: "collection-own.test") { request in
            request.query["parentId"] == "c1" ? page : nil
        }

        let found = try await session(host: "collection-own.test").collectionQueue(id: "c1", shuffled: false)

        #expect(found.items.map(\.id) == ["m1", "e1"])
        #expect(found.skippedCount == 1)
        #expect(found.overLimitCount == 0)
        // Only the page's own request: nothing asked for everything in it at once.
        let page = try #require(recorder.requests.only)
        #expect(page.query["sortBy"] == "Default")
        #expect(page.query["recursive"] != "true")
    }

    @Test func `a series plays its episodes where the page lists it, in order however it's sorted`() async throws {
        let recorder = register(host: "collection-series.test") { request in
            switch request.query["parentId"] {
            // Sorted descending, the page lists the series between the movies.
            case "c1": Self.items([Self.movie("m2"), Self.series("s1"), Self.movie("m1")])
            case "s1": Self.items([Self.episode("e1"), Self.episode("e2")])
            default: nil
            }
        }
        var filter = LibraryFilter()
        filter.played = false

        let found = try await session(host: "collection-series.test").collectionQueue(
            id: "c1",
            shuffled: false,
            sort: LibrarySort(.default, .descending),
            filter: filter,
        )

        #expect(found.items.map(\.id) == ["m2", "e1", "e2", "m1"])
        let episodes = try #require(recorder.requests.first { $0.query["parentId"] == "s1" })
        #expect(episodes.query["recursive"] == "true")
        #expect(episodes.query["includeItemTypes"] == Self.videoTypes)
        #expect(episodes.query["sortBy"] == "ParentIndexNumber,IndexNumber,SortName")
        #expect(episodes.query["sortOrder"] == "Ascending,Ascending,Ascending")
        #expect(episodes.query["excludeLocationTypes"] == "Virtual")
        #expect(episodes.query["isPlayed"] == "false")
        // No more than fit in the queue after the movie before it.
        #expect(episodes.query["limit"] == "99")
        #expect(recorder.requests.first { $0.query["parentId"] == "c1" }?.query["sortOrder"] == "Descending")
    }

    @Test func `what a collection inside it holds plays where that collection is, in its own order`() async throws {
        let recorder = register(host: "collection-nested.test") { request in
            switch request.query["parentId"] {
            case "c1": Self.items([Self.movie("m1"), Self.boxSet("b1"), Self.movie("m2")])
            // It holds the outer collection too, which isn't gone through again.
            case "b1": Self.items([Self.movie("m3"), Self.series("s2"), Self.boxSet("c1"), Self.movie("m1")])
            case "s2": Self.items([Self.episode("e1")])
            default: nil
            }
        }

        let found = try await session(host: "collection-nested.test").collectionQueue(id: "c1", shuffled: false)

        // Not at the end, as before, and m1 once.
        #expect(found.items.map(\.id) == ["m1", "m3", "e1", "m2"])
        #expect(recorder.requests.count(where: { $0.query["parentId"] == "c1" }) == 1)
        let inner = try #require(recorder.requests.first { $0.query["parentId"] == "b1" })
        #expect(inner.query["sortBy"] == "Default")
        #expect(inner.query["sortOrder"] == "Ascending")
    }

    @Test func `the page's items aren't asked for again`() async throws {
        let recorder = register(host: "collection-shown.test") { _ in Self.items([]) }
        let shown = [
            ItemDetails(item: MediaItem(id: "m2", name: "Film m2", kind: .movie)),
            ItemDetails(item: MediaItem(id: "m1", name: "Film m1", kind: .movie)),
        ]

        let found = try await session(host: "collection-shown.test")
            .collectionQueue(id: "c1", shuffled: false, shown: shown)

        #expect(found.items.map(\.id) == ["m2", "m1"])
        #expect(recorder.requests.isEmpty)
    }

    @Test func `a collection larger than a queue plays its first 100 videos and counts the rest`() async throws {
        // Songs first, then 110 movies: before, the first 100 items were cut before leaving out the
        // songs, so 97 movies played.
        let songs = (1 ... 3).map { Self.song("a\($0)") }
        let movies = (1 ... 110).map { Self.movie("m\($0)") }
        let recorder = register(host: "collection-big.test") { request in
            guard request.query["limit"] == "0" else { return Self.items(songs + movies) }
            let count = request.query["includeItemTypes"] == Self.videoTypes ? 110 : 113
            return #"{"Items":[],"TotalRecordCount":\#(count)}"#
        }

        let found = try await session(host: "collection-big.test").collectionQueue(id: "c1", shuffled: false)

        #expect(found.items.count == 100)
        #expect(found.items.first?.id == "m1")
        #expect(found.items.last?.id == "m100")
        #expect(found.overLimitCount == 10)
        #expect(found.skippedCount == 3)
        let counts = recorder.requests.filter { $0.query["limit"] == "0" }
        #expect(counts.count == 2)
        #expect(counts.allSatisfy { $0.query["recursive"] == "true" && $0.query["enableTotalRecordCount"] == "true" })
        #expect(counts.allSatisfy { $0.query["filters"] == "IsNotFolder" })
    }

    @Test func `shuffled, the server picks up to 100 videos and counts the rest`() async throws {
        let movies = (1 ... 100).map { Self.movie("m\($0)") }
        let recorder = register(host: "collection-random.test") { request in
            request.query["limit"] == "0"
                ? #"{"Items":[],"TotalRecordCount":135}"#
                : #"{"Items":[\#(movies.joined(separator: ","))],"TotalRecordCount":130}"#
        }

        let found = try await session(host: "collection-random.test").collectionQueue(id: "c1", shuffled: true)

        #expect(found.items.count == 100)
        #expect(found.overLimitCount == 30)
        #expect(found.skippedCount == 5)
        let request = try #require(recorder.requests.first { $0.query["limit"] == "100" })
        #expect(request.query["sortBy"] == "Random")
        #expect(request.query["recursive"] == "true")
        #expect(request.query["includeItemTypes"] == Self.videoTypes)
        #expect(request.query["excludeLocationTypes"] == "Virtual")
        let count = try #require(recorder.requests.first { $0.query["limit"] == "0" })
        #expect(count.query["includeItemTypes"] == nil)
    }

    @Test func `a collection plays in the sort and with the filters its page shows`() async throws {
        let recorder = register(host: "collection-sort.test") { _ in Self.items([]) }
        var filter = LibraryFilter()
        filter.played = false

        _ = try await session(host: "collection-sort.test").collectionQueue(
            id: "c1",
            shuffled: false,
            sort: LibrarySort(.premiereDate, .descending),
            filter: filter,
        )

        let request = try #require(recorder.requests.first { $0.query["limit"] == "100" })
        #expect(request.query["sortBy"] == "PremiereDate,SortName")
        #expect(request.query["sortOrder"] == "Descending,Ascending")
        #expect(request.query["isPlayed"] == "false")
        #expect(request.query["recursive"] == "true")
        #expect(request.query["filters"] == "IsNotFolder")
        #expect(request.query["includeItemTypes"] == Self.videoTypes)
        #expect(request.query["excludeItemIds"] == "c1")
        #expect(recorder.requests.first { $0.query["limit"] == "0" }?.query["isPlayed"] == "false")
    }

    private static func items(_ items: [String]) -> String {
        QueuesTests.items(items)
    }

    private static func movie(_ id: String) -> String {
        #"{"Id":"\#(id)","Name":"Film \#(id)","Type":"Movie"}"#
    }

    private static func song(_ id: String) -> String {
        #"{"Id":"\#(id)","Name":"Song \#(id)","Type":"Audio"}"#
    }

    private static func series(_ id: String) -> String {
        #"{"Id":"\#(id)","Name":"Show \#(id)","Type":"Series","IsFolder":true}"#
    }

    private static func boxSet(_ id: String) -> String {
        #"{"Id":"\#(id)","Name":"Box \#(id)","Type":"BoxSet","IsFolder":true}"#
    }

    private static func episode(_ id: String) -> String {
        QueuesTests.episode(id, season: 1, number: 1)
    }
}

private extension Array {
    /// The one element, if there's exactly one.
    var only: Element? {
        count == 1 ? first : nil
    }
}
