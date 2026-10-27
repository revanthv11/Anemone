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
            case "/Playlists/pl1/Items":
                return .json(#"{"Items":[{"Id":"m1","Name":"Film","Type":"Movie","PlaylistItemId":"entry-7"}]}"#)
            case "/Playlists/pl3/Items":
                return .json(#"{"Items":[{"Id":"m2","Name":"Other","Type":"Movie"}]}"#)
            default:
                return nil
            }
        }

        let playlists = try await session(host: "playlists.test").editablePlaylists(for: "m1")

        #expect(playlists == [
            EditablePlaylist(id: "pl1", name: "Mine", itemCount: 2, entryID: "entry-7"),
            EditablePlaylist(id: "pl3", name: "Shared", itemCount: 0),
        ])
        let query = try #require(listed.request?.query)
        #expect(query["includeItemTypes"] == "Playlist")
        #expect(query["sortBy"] == "DateLastContentAdded")
        #expect(query["sortOrder"] == "Descending")
        #expect(query["limit"] == "25")
        #expect(query["recursive"] == "true")
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
