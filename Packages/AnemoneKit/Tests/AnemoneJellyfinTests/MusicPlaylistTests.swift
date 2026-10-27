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

    @Test func `a playlist of songs comes in one request, for Play before its page has loaded`() async throws {
        let sent = register(
            host: "music-playlist-songs.test",
            path: "/jf/Playlists/pl1/Items",
            reply: .json(#"{"Items":[\#(Self.song)],"TotalRecordCount":1}"#),
        )

        let songs = try await session(host: "music-playlist-songs.test").playlistSongs("pl1")

        #expect(songs?.map(\.id) == ["s1"])
        let query = try #require(sent.request).query
        #expect(query["limit"] == nil)
        #expect(query["fields"]?.contains("MediaStreams") == true)
    }

    @Test func `a playlist with anything but songs isn't played as music`() async throws {
        _ = register(
            host: "music-playlist-mixed.test",
            path: "/jf/Playlists/pl1/Items",
            reply: .json(#"{"Items":[\#(Self.song),{"Id":"v1","Name":"Clip","Type":"Video"}],"TotalRecordCount":2}"#),
        )
        _ = register(
            host: "music-playlist-empty.test",
            path: "/jf/Playlists/pl1/Items",
            reply: .json(#"{"Items":[],"TotalRecordCount":0}"#),
        )

        #expect(try await session(host: "music-playlist-mixed.test").playlistSongs("pl1") == nil)
        #expect(try await session(host: "music-playlist-empty.test").playlistSongs("pl1") == nil)
    }
}
