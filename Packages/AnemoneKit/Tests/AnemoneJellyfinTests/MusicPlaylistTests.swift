import AnemoneJellyfin
import Foundation
import Testing

/// A playlist's songs, which come from the playlist's own endpoint. Its entries that aren't
/// songs are left out, but still counted, so pages line up with the server's.
struct MusicPlaylistTests {
    private func session(host: String) throws -> JellyfinSession {
        try JellyfinSession(
            serverURL: #require(URL(string: "https://\(host)/jf")),
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

    private static let song = """
    {"Id":"s1","Name":"Jellyfin","Type":"Audio","Album":"Nemesis","AlbumId":"al1",
     "AlbumPrimaryImageTag":"cover","Artists":["Leap Fidei","Guest"],
     "ArtistItems":[{"Id":"ar1","Name":"Leap Fidei"},{"Id":"ar2","Name":"Guest"}],"IndexNumber":3,
     "ParentIndexNumber":1,"HasLyrics":true,"RunTimeTicks":1800000000,
     "MediaStreams":[{"Type":"Audio","Codec":"flac","Channels":6},{"Type":"EmbeddedImage","Codec":"mjpeg"}]}
    """

    @Test func `a playlist's songs come in the playlist's own order, songs only`() async throws {
        let sent = register(
            host: "music-playlist.test",
            path: "/jf/Playlists/pl1/Items",
            reply: .json(#"{"Items":[\#(Self.song),{"Id":"v1","Name":"Clip","Type":"Video"}],"TotalRecordCount":2}"#),
        )
        let session = try session(host: "music-playlist.test")

        let page = try await session.songs(from: .playlist("pl1"), startIndex: 0, limit: 100)

        let request = try #require(sent.request)
        #expect(request.method == "GET")
        #expect(request.query["userId"] == "u1")
        #expect(request.query["startIndex"] == "0")
        #expect(request.query["limit"] == "100")
        #expect(request.query["fields"]?.contains("MediaStreams") == true)
        // The playlist's own order, not one the request picks.
        #expect(request.query["sortBy"] == nil)
        #expect(page.items.map(\.id) == ["s1"])
        #expect(page.totalCount == 2)
        // The clip is counted, so the next page starts after it.
        #expect(page.serverCount == 2)
    }

    @Test func `a later page of a playlist counts what the server sent`() async throws {
        let sent = register(
            host: "music-playlist-later.test",
            path: "/jf/Playlists/pl1/Items",
            reply: .json(#"{"Items":[{"Id":"v1","Name":"Clip","Type":"Video"},\#(Self.song)]}"#),
        )

        let page = try await session(host: "music-playlist-later.test")
            .songs(from: .playlist("pl1"), startIndex: 100, limit: 100)

        #expect(try #require(sent.request).query["startIndex"] == "100")
        #expect(page.items.map(\.id) == ["s1"])
        #expect(page.totalCount == nil)
        #expect(page.serverCount == 2)
    }

    @Test func `a playlist's page says whether its entries are all songs, by their type`() async throws {
        _ = register(
            host: "music-playlist-songs.test",
            path: "/jf/Playlists/pl1/Items",
            reply: .json(#"{"Items":[\#(Self.song)],"TotalRecordCount":1}"#),
        )
        _ = register(
            host: "music-playlist-mixed.test",
            path: "/jf/Playlists/pl1/Items",
            reply: .json(#"{"Items":[\#(Self.song),{"Id":"v1","Name":"Clip","Type":"Video"}],"TotalRecordCount":2}"#),
        )

        let songs = try await session(host: "music-playlist-songs.test")
            .songs(from: .playlist("pl1"), startIndex: 0, limit: 100)
        let mixed = try await session(host: "music-playlist-mixed.test")
            .songs(from: .playlist("pl1"), startIndex: 0, limit: 100)

        #expect(songs.isAllSongs)
        #expect(!mixed.isAllSongs)
    }

    @Test func `a song that can't be read still counts as a song`() async throws {
        // The second entry is a song without an ID, which the app can't read or play. It isn't
        // something else, so the playlist is still music, and the song is left out.
        _ = register(
            host: "music-playlist-unread.test",
            path: "/jf/Playlists/pl1/Items",
            reply: .json(#"{"Items":[\#(Self.song),{"Name":"Broken","Type":"Audio"}],"TotalRecordCount":2}"#),
        )

        let page = try await session(host: "music-playlist-unread.test")
            .songs(from: .playlist("pl1"), startIndex: 0, limit: 100)

        #expect(page.isAllSongs)
        #expect(page.items.map(\.id) == ["s1"])
        #expect(page.serverCount == 2)
    }
}
