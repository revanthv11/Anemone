import AnemoneJellyfin
import Foundation
import Synchronization
import Testing

/// Item page extras against the fake server: chapters, trailers, special features, delete and
/// the collection page's sort and filter.
struct ItemExtrasTests {
    private func session(host: String) throws -> JellyfinSession {
        try JellyfinSession(
            serverURL: #require(URL(string: "https://\(host)")),
            userID: "u1",
            accessToken: "tok",
            identity: ClientIdentity(deviceName: "Test TV", deviceID: "device-1", appVersion: "0.1.0"),
            sessionConfiguration: { MockServer.sessionConfiguration() },
        )
    }

    /// Answers each path with its reply, recording every request by path.
    private func register(host: String, replies: [String: MockServer.Reply]) -> PathRecorder {
        let paths = PathRecorder()
        MockServer.register(host: host) { request in
            guard let path = request.url?.path(), let reply = replies[path] else { return nil }
            paths.sent.withLock { $0[path] = SentRequest(request) }
            return reply
        }
        return paths
    }

    @Test func `chapters come in order of where they start, keeping their image index`() async throws {
        _ = register(host: "chapters.test", replies: ["/Items/m1": .json(#"""
        {"Id":"m1","Name":"Film","Type":"Movie","Chapters":[
          {"Name":"Opening","StartPositionTicks":0,"ImageTag":"c0"},
          {"Name":"Finale","StartPositionTicks":1200000000,"ImageTag":"c1"},
          {"Name":"","StartPositionTicks":300000000}
        ]}
        """#)])
        let session = try session(host: "chapters.test")

        let chapters = try await session.itemExtras(id: "m1").chapters

        #expect(chapters.map(\.name) == ["Opening", nil, "Finale"])
        #expect(chapters.map(\.start) == [.zero, .seconds(30), .seconds(120)])
        #expect(chapters.map(\.index) == [0, 2, 1])
        #expect(chapters[1].imageTag == nil)
        let url = try #require(session.imageURL(for: chapters[2], maxWidth: 680))
        #expect(url.path() == "/Items/m1/Images/Chapter/1")
        #expect(url.queryValues["tag"] == "c1")
        #expect(url.queryValues["maxWidth"] == "680")
        #expect(session.imageURL(for: chapters[1], maxWidth: 680) == nil)
    }

    @Test func `local trailers come first, then official trailers, others and teasers`() async throws {
        let paths = register(host: "trailers.test", replies: [
            "/Items/m1": .json(#"""
            {"Id":"m1","Name":"Film","Type":"Movie","LocalTrailerCount":1,"RemoteTrailers":[
              {"Name":"Teaser","Url":"https://www.youtube.com/watch?v=t1"},
              {"Name":"Behind the Music","Url":"https://vimeo.com/123"},
              {"Name":"Film - Official Trailer","Url":"https://www.youtube.com/watch?v=o1"},
              {"Url":"https://youtu.be/x1"},
              {"Name":"Broken"}
            ]}
            """#),
            "/Items/m1/LocalTrailers": .json(#"[{"Id":"lt1","Name":"Film Trailer","Type":"Trailer"}]"#),
        ])

        let trailers = try await session(host: "trailers.test").itemExtras(id: "m1").trailers

        #expect(trailers.map(\.name) == [
            "Film Trailer",
            "Film - Official Trailer",
            "Trailer",
            "Behind the Music",
            "Teaser",
        ])
        #expect(trailers.map(\.sourceName) == ["Local", "YouTube", "YouTube", "External", "YouTube"])
        #expect(paths.request("/Items/m1/LocalTrailers")?.query["userId"] == "u1")
        guard case let .local(details) = trailers.first?.source else {
            Issue.record("The local trailer should come first")
            return
        }
        #expect(details.id == "lt1")
    }

    @Test func `local trailers and special features are asked for only when there are some`() async throws {
        let paths = register(host: "none.test", replies: [
            "/Items/m1": .json(
                #"{"Id":"m1","Name":"Film","Type":"Movie","LocalTrailerCount":0,"SpecialFeatureCount":0}"#,
            ),
        ])

        let extras = try await session(host: "none.test").itemExtras(id: "m1")

        #expect(extras.trailers.isEmpty)
        #expect(extras.features.isEmpty)
        #expect(paths.request("/Items/m1/LocalTrailers") == nil)
        #expect(paths.request("/Items/m1/SpecialFeatures") == nil)
    }

    @Test func `special features are asked for when the server doesn't count them`() async throws {
        let paths = register(host: "uncounted.test", replies: [
            "/Items/m1": .json(#"{"Id":"m1","Name":"Film","Type":"Movie"}"#),
            "/Items/m1/SpecialFeatures": .json("[]"),
        ])

        _ = try await session(host: "uncounted.test").itemExtras(id: "m1")

        #expect(paths.request("/Items/m1/SpecialFeatures") != nil)
    }

    @Test func `remote trailers still show when local trailers and special features fail to load`() async throws {
        _ = register(host: "local-fails.test", replies: [
            "/Items/m1": .json(#"""
            {"Id":"m1","Name":"Film","Type":"Movie","LocalTrailerCount":2,
             "RemoteTrailers":[{"Name":"Trailer","Url":"https://www.youtube.com/watch?v=a"}]}
            """#),
            "/Items/m1/LocalTrailers": MockServer.Reply(status: 500, body: ""),
            "/Items/m1/SpecialFeatures": MockServer.Reply(status: 500, body: ""),
        ])

        let extras = try await session(host: "local-fails.test").itemExtras(id: "m1")

        #expect(extras.trailers.map(\.name) == ["Trailer"])
        #expect(extras.features.isEmpty)
    }

    @Test func `a YouTube trailer opens in the YouTube app`() throws {
        func appURL(_ link: String) throws -> String? {
            try Trailer(name: "Trailer", source: .remote(#require(URL(string: link)))).youTubeAppURL?.absoluteString
        }

        #expect(try appURL("https://www.youtube.com/watch?v=abc") == "youtube://https://www.youtube.com/watch?v=abc")
        #expect(try appURL("https://youtu.be/abc") == "youtube://https://youtu.be/abc")
        #expect(try appURL("https://m.youtube.com/watch?v=abc") == "youtube://https://m.youtube.com/watch?v=abc")
        #expect(try appURL("https://vimeo.com/123") == nil)
        #expect(try appURL("https://notyoutube.com/watch?v=abc") == nil)
    }

    @Test func `extras are grouped by kind in Wholphin's order, without trailers or theme music`() async throws {
        let paths = register(host: "extras.test", replies: [
            "/Items/m1": .json(#"{"Id":"m1","Name":"Film","Type":"Movie","SpecialFeatureCount":7}"#),
            "/Items/m1/SpecialFeatures": .json(#"""
            [
              {"Id":"x1","Name":"Making Of","Type":"Video","ExtraType":"BehindTheScenes"},
              {"Id":"x2","Name":"Part One","Type":"Video","ExtraType":"Featurette",
               "UserData":{"Key":"x2","Played":true}},
              {"Id":"x3","Name":"","Type":"Video","ExtraType":"DeletedScene",
               "UserData":{"Key":"x3","PlayedPercentage":50}},
              {"Id":"x4","Name":"Part Two","Type":"Video","ExtraType":"Featurette",
               "UserData":{"Key":"x4","Played":true}},
              {"Id":"x5","Name":"Theme","Type":"Audio","ExtraType":"ThemeSong"},
              {"Id":"x6","Name":"Trailer","Type":"Video","ExtraType":"Trailer"},
              {"Id":"x7","Name":"Mystery","Type":"Video"}
            ]
            """#),
        ])

        let extras = try await session(host: "extras.test").itemExtras(id: "m1").features

        #expect(extras.map(\.kind) == [.featurette, .deletedScene, .behindTheScenes, .other])
        #expect(extras.map(\.title) == ["Featurettes", "Deleted scene", "Making Of", "Mystery"])
        #expect(extras.map(\.subtitle) == ["2 items", nil, "Behind the scenes", "Other"])
        #expect(extras.first?.items.map(\.id) == ["x2", "x4"])
        #expect(extras.map(\.isPlayed) == [true, false, false, false])
        #expect(extras.map(\.progress) == [nil, 0.5, nil, nil])
        #expect(paths.request("/Items/m1/SpecialFeatures")?.query["userId"] == "u1")
    }

    @Test func `whether the item can be deleted comes from the server`() async throws {
        _ = register(host: "can-delete.test", replies: [
            "/Items/m1": .json(#"{"Id":"m1","Name":"Film","Type":"Movie","CanDelete":true}"#),
            "/Items/m2": .json(#"{"Id":"m2","Name":"Other","Type":"Movie"}"#),
        ])
        let session = try session(host: "can-delete.test")

        let deletable = try await session.itemExtras(id: "m1")
        let kept = try await session.itemExtras(id: "m2")

        #expect(deletable.canDelete)
        #expect(deletable.itemID == "m1")
        #expect(!kept.canDelete)
    }

    @Test func `asking only whether an item can be deleted sends one request`() async throws {
        let paths = register(host: "can-delete-only.test", replies: [
            "/Items/c1": .json(#"{"Id":"c1","Name":"Saga","Type":"BoxSet","CanDelete":true,"LocalTrailerCount":1}"#),
            "/Items/c2": .json(#"{"Id":"c2","Name":"Other Saga","Type":"BoxSet"}"#),
            "/Items/c1/LocalTrailers": .json("[]"),
            "/Items/c1/SpecialFeatures": .json("[]"),
            "/Items/c2/SpecialFeatures": .json("[]"),
        ])
        let session = try session(host: "can-delete-only.test")

        let deletable = try await session.canDelete(id: "c1")
        let kept = try await session.canDelete(id: "c2")

        #expect(deletable)
        #expect(!kept)
        #expect(paths.sent.withLock { $0.keys.sorted() } == ["/Items/c1", "/Items/c2"])
        #expect(paths.request("/Items/c1")?.query["userId"] == "u1")
    }

    @Test func `deleting sends DELETE for the item`() async throws {
        let paths = register(host: "delete.test", replies: ["/Items/m1": MockServer.Reply(status: 204, body: "")])

        try await session(host: "delete.test").deleteItem(id: "m1")

        #expect(paths.request("/Items/m1")?.method == "DELETE")
    }

    @Test func `a refused delete throws`() async throws {
        MockServer.register(host: "delete-refused.test") { _ in MockServer.Reply(status: 403, body: "") }
        MockServer.register(host: "delete-revoked.test") { _ in .unauthorized }

        await #expect(throws: (any Error).self) {
            try await session(host: "delete-refused.test").deleteItem(id: "m1")
        }
        await #expect(throws: SessionError.signedOut) {
            try await session(host: "delete-revoked.test").deleteItem(id: "m1")
        }
    }

    @Test func `extras report a revoked token as signed out`() async throws {
        MockServer.register(host: "revoked-extras.test") { _ in .unauthorized }

        await #expect(throws: SessionError.signedOut) {
            try await session(host: "revoked-extras.test").itemExtras(id: "m1")
        }
    }

    @Test func `a collection's items come in its own order by default`() async throws {
        let paths = register(host: "collection.test", replies: ["/Items": .json(#"""
        {"Items":[{"Id":"m1","Name":"First","Type":"Movie"},{"Id":"s1","Name":"Show","Type":"Series"}]}
        """#)])

        let items = try await session(host: "collection.test").collectionItems(
            id: "c1",
            sort: LibrarySort(.default),
            filter: LibraryFilter(),
        )

        #expect(items.map(\.id) == ["m1", "s1"])
        let query = try #require(paths.request("/Items")).query
        #expect(query["parentId"] == "c1")
        #expect(query["recursive"] == "false")
        #expect(query["sortBy"] == "Default")
        #expect(query["sortOrder"] == "Ascending")
        #expect(query["enableUserData"] == "true")
        #expect(query["fields"]?.contains("Overview") == true)
        #expect(query["isPlayed"] == nil)
    }

    @Test func `a collection's items follow the chosen sort and filter`() async throws {
        let paths = register(host: "collection-sorted.test", replies: ["/Items": .json(#"{"Items":[]}"#)])
        var filter = LibraryFilter()
        filter.played = false
        filter.genres = ["g1"]

        _ = try await session(host: "collection-sorted.test").collectionItems(
            id: "c1",
            sort: LibrarySort(.premiereDate, .descending),
            filter: filter,
        )

        let query = try #require(paths.request("/Items")).query
        #expect(query["sortBy"] == "PremiereDate,SortName")
        #expect(query["sortOrder"] == "Descending,Ascending")
        #expect(query["isPlayed"] == "false")
        #expect(query["genreIds"] == "g1")
    }
}

/// Every request a test's fake server saw, by path.
private final class PathRecorder: Sendable {
    let sent = Mutex<[String: SentRequest]>([:])

    func request(_ path: String) -> SentRequest? {
        sent.withLock { $0[path] }
    }
}

/// Reloading the Extras row after one of its extras has played.
extension ItemExtrasTests {
    @Test func `after an extra plays, only the special features' user state is asked for again`() async throws {
        let paths = register(host: "extras-reload.test", replies: [
            "/Items/m1/SpecialFeatures": .json(#"""
            [
              {"Id":"x1","Name":"Making Of","Type":"Video","ExtraType":"BehindTheScenes",
               "UserData":{"Key":"x1","Played":true}},
              {"Id":"x2","Name":"Part One","Type":"Video","ExtraType":"Featurette",
               "UserData":{"Key":"x2","PlaybackPositionTicks":300000000,"PlayedPercentage":25}}
            ]
            """#),
        ])
        let making = ItemDetails(item: MediaItem(id: "x1", name: "Making Of", kind: .video))
        let partOne = ItemDetails(item: MediaItem(id: "x2", name: "Part One", kind: .video))
        let partTwo = ItemDetails(
            item: MediaItem(id: "x3", name: "Part Two", kind: .video),
            userState: .init(isPlayed: true),
        )
        var extras = ItemExtras(
            itemID: "m1",
            chapters: [Chapter(itemID: "m1", index: 0, name: "Opening", start: .zero)],
            features: [
                ExtrasEntry(kind: .featurette, items: [partOne, partTwo]),
                ExtrasEntry(kind: .behindTheScenes, items: [making]),
            ],
            canDelete: true,
        )

        try await extras.updateFeatures(session(host: "extras-reload.test").specialFeatureStates(id: "m1"))

        #expect(paths.sent.withLock { $0.keys.sorted() } == ["/Items/m1/SpecialFeatures"])
        #expect(extras.features.map(\.kind) == [.featurette, .behindTheScenes])
        #expect(extras.features[1].isPlayed)
        let reloaded = extras.features[0].items
        #expect(reloaded.map(\.userState.resumePosition) == [.seconds(30), nil])
        #expect(reloaded.map(\.item.progress) == [0.25, nil])
        // The server didn't name it, so it keeps what it had.
        #expect(reloaded[1].userState.isPlayed)
        // The rest of the extras stay as they were.
        #expect(extras.chapters.count == 1)
        #expect(extras.canDelete)
    }

    @Test func `a failed special features reload throws, so the row can keep its extras`() async throws {
        _ = register(host: "extras-reload-fails.test", replies: [
            "/Items/m1/SpecialFeatures": MockServer.Reply(status: 500, body: ""),
        ])
        MockServer.register(host: "extras-reload-revoked.test") { _ in .unauthorized }

        await #expect(throws: (any Error).self) {
            try await session(host: "extras-reload-fails.test").specialFeatureStates(id: "m1")
        }
        await #expect(throws: SessionError.signedOut) {
            try await session(host: "extras-reload-revoked.test").specialFeatureStates(id: "m1")
        }
    }
}
