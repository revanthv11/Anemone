import AnemoneJellyfin
import Foundation
import Synchronization
import Testing

/// "Add to playlist", after Wholphin's `AddPlaylistViewModel` and `PlaylistCreator`.
struct PlaylistEditingTests {
    private func session(host: String) throws -> JellyfinSession {
        try JellyfinSession(
            serverURL: #require(URL(string: "https://\(host)")),
            userID: "u1",
            accessToken: "tok",
            identity: ClientIdentity(deviceName: "Test TV", deviceID: "device-1", appVersion: "0.1.0"),
            sessionConfiguration: { MockServer.sessionConfiguration() },
        )
    }

    @Test func `offers the newest playlists the user may edit, saying which hold the item`() async throws {
        let listed = Recorder()
        MockServer.register(host: "playlists.test") { request in
            switch request.url?.path() {
            case "/Items":
                listed.last.withLock { $0 = SentRequest(request) }
                return .json(#"""
                {"Items":[{"Id":"pl1","Name":"Mine","Type":"Playlist","ChildCount":2},
                          {"Id":"pl2","Name":"Theirs","Type":"Playlist","ChildCount":5},
                          {"Id":"pl3","Name":"Shared","Type":"Playlist"}]}
                """#)
            case "/Playlists/pl1/Users/u1", "/Playlists/pl3/Users/u1":
                return .json(#"{"UserId":"u1","CanEdit":true}"#)
            case "/Playlists/pl2/Users/u1":
                return MockServer.Reply(status: 404, body: "")
            case "/Playlists/pl1":
                return .json(#"{"ItemIds":["m2","m1"],"Shares":[],"OpenAccess":false}"#)
            case "/Playlists/pl3":
                return .json(#"{"ItemIds":["m2"],"Shares":[],"OpenAccess":true}"#)
            default:
                return nil
            }
        }

        let playlists = try await session(host: "playlists.test").editablePlaylists(for: "m1")

        #expect(playlists == [
            EditablePlaylist(id: "pl1", name: "Mine", itemCount: 2, holdsItem: true),
            EditablePlaylist(id: "pl3", name: "Shared", itemCount: 0),
        ])
        let query = try #require(listed.request?.query)
        #expect(query["includeItemTypes"] == "Playlist")
        #expect(query["sortBy"] == "DateLastContentAdded")
        #expect(query["sortOrder"] == "Descending")
        #expect(query["limit"] == "25")
        #expect(query["recursive"] == "true")
    }

    @Test func `a playlist that can't be checked is still offered, and no entries are read`() async throws {
        let server = HomeServer("playlists-partial.test") { path, _ in
            switch path {
            case "/Items":
                .homeItems(
                    #"{"Id":"pl1","Name":"Broken","Type":"Playlist","ChildCount":900}"#,
                    #"{"Id":"pl2","Name":"Fine","Type":"Playlist","ChildCount":3}"#,
                )
            case "/Playlists/pl1/Users/u1", "/Playlists/pl2/Users/u1":
                .json(#"{"UserId":"u1","CanEdit":true}"#)
            case "/Playlists/pl1":
                MockServer.Reply(status: 500, body: "")
            case "/Playlists/pl2":
                .json(#"{"ItemIds":["0F5E1B9A-2C3D-4E5F-6A7B-8C9D0E1F2A3B"],"Shares":[]}"#)
            default:
                nil
            }
        }

        let playlists = try await server.session().editablePlaylists(for: "0f5e1b9a2c3d4e5f6a7b8c9d0e1f2a3b")

        #expect(playlists == [
            EditablePlaylist(id: "pl1", name: "Broken", itemCount: 900),
            EditablePlaylist(id: "pl2", name: "Fine", itemCount: 3, holdsItem: true),
        ])
        #expect(!server.paths.contains { $0.hasSuffix("/Items") && $0.hasPrefix("/Playlists") })
    }

    @Test func `taking an item out finds its entry first`() async throws {
        let server = HomeServer("playlist-take-out.test") { path, request in
            switch (path, request.method) {
            case ("/Playlists/pl1/Items", "GET"):
                .homeItems(
                    #"{"Id":"m2","Name":"Other","Type":"Movie","PlaylistItemId":"entry-3"}"#,
                    #"{"Id":"m1","Name":"Film","Type":"Movie","PlaylistItemId":"entry-7"}"#,
                )
            case ("/Playlists/pl1/Items", "DELETE"):
                MockServer.Reply(status: 204, body: "")
            default:
                nil
            }
        }

        try await server.session().removeFromPlaylist("pl1", itemID: "m1")

        let sent = server.requests(to: "/Playlists/pl1/Items")
        #expect(sent.map(\.method) == ["GET", "DELETE"])
        #expect(sent.last?.query["entryIds"] == "entry-7")
    }

    @Test func `taking an item out finds its entry however the server writes its ID`() async throws {
        let server = HomeServer("playlist-take-out-dashed.test") { path, request in
            switch (path, request.method) {
            case ("/Playlists/pl1/Items", "GET"):
                .homeItems(#"{"Id":"0F5E1B9A-2C3D-4E5F-6A7B-8C9D0E1F2A3B","Type":"Movie","PlaylistItemId":"e9"}"#)
            case ("/Playlists/pl1/Items", "DELETE"):
                MockServer.Reply(status: 204, body: "")
            default:
                nil
            }
        }

        try await server.session().removeFromPlaylist("pl1", itemID: "0f5e1b9a2c3d4e5f6a7b8c9d0e1f2a3b")

        #expect(server.requests(to: "/Playlists/pl1/Items").last?.query["entryIds"] == "e9")
    }

    @Test func `taking out an item the playlist doesn't hold fails without removing anything`() async throws {
        let server = HomeServer("playlist-take-out-missing.test") { path, request in
            switch (path, request.method) {
            case ("/Playlists/pl1/Items", "GET"):
                .homeItems(#"{"Id":"m2","Name":"Other","Type":"Movie","PlaylistItemId":"entry-3"}"#)
            case ("/Playlists/pl1/Items", "DELETE"):
                MockServer.Reply(status: 204, body: "")
            default:
                nil
            }
        }

        await #expect(throws: PlaylistEditingError.notInPlaylist) {
            try await server.session().removeFromPlaylist("pl1", itemID: "m1")
        }
        #expect(server.requests(to: "/Playlists/pl1/Items").map(\.method) == ["GET"])
    }

    @Test func `adds an item to the end of a playlist`() async throws {
        let sent = Recorder()
        MockServer.register(host: "playlist-add.test") { request in
            guard request.url?.path() == "/Playlists/pl1/Items" else { return nil }
            sent.last.withLock { $0 = SentRequest(request) }
            return MockServer.Reply(status: 204, body: "")
        }

        try await session(host: "playlist-add.test").addToPlaylist("pl1", itemID: "m1")

        #expect(sent.request?.method == "POST")
        #expect(sent.request?.query["ids"] == "m1")
        #expect(sent.request?.query["userId"] == "u1")
    }

    @Test func `takes an entry out of a playlist`() async throws {
        let sent = Recorder()
        MockServer.register(host: "playlist-remove.test") { request in
            guard request.url?.path() == "/Playlists/pl1/Items" else { return nil }
            sent.last.withLock { $0 = SentRequest(request) }
            return MockServer.Reply(status: 204, body: "")
        }

        try await session(host: "playlist-remove.test").removeFromPlaylist("pl1", entryID: "entry-7")

        #expect(sent.request?.method == "DELETE")
        #expect(sent.request?.query["entryIds"] == "entry-7")
    }

    @Test func `reports a revoked token while listing playlists`() async throws {
        MockServer.register(host: "playlists-revoked.test") { request in
            request.url?.path() == "/Items" ? .json(#"{"Items":[{"Id":"pl1","Type":"Playlist"}]}"#) : .unauthorized
        }

        await #expect(throws: SessionError.signedOut) {
            try await session(host: "playlists-revoked.test").editablePlaylists(for: "m1")
        }
    }
}
