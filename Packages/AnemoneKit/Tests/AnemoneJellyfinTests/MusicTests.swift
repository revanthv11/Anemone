import AnemoneJellyfin
import Foundation
import Synchronization
import Testing

/// Music lists, pages and streams from the fake server, and the rules ported with them.
struct MusicTests {
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

    private static let album = """
    {"Id":"al1","Name":"Nemesis","Type":"MusicAlbum","ProductionYear":2024,"AlbumArtist":"Leap Fidei",
     "AlbumArtists":[{"Id":"ar1","Name":"Leap Fidei"}],"Artists":["Leap Fidei"],
     "ArtistItems":[{"Id":"ar1","Name":"Leap Fidei"}],"ImageTags":{"Primary":"cover"},"SongCount":1,
     "UserData":{"Key":"al1","IsFavorite":true}}
    """

    private static let song = """
    {"Id":"s1","Name":"Jellyfin","Type":"Audio","Album":"Nemesis","AlbumId":"al1",
     "AlbumPrimaryImageTag":"cover","Artists":["Leap Fidei","Guest"],
     "ArtistItems":[{"Id":"ar1","Name":"Leap Fidei"},{"Id":"ar2","Name":"Guest"}],"IndexNumber":3,
     "ParentIndexNumber":1,"HasLyrics":true,"RunTimeTicks":1800000000,
     "MediaStreams":[{"Type":"Audio","Codec":"flac","Channels":6},{"Type":"EmbeddedImage","Codec":"mjpeg"}]}
    """

    @Test func `the albums tab asks for the library's albums a page at a time, sorted`() async throws {
        let sent = register(host: "music-albums.test", path: "/jf/Items", reply: .json("""
        {"Items":[\(Self.album)],"TotalRecordCount":4}
        """))

        let page = try await session(host: "music-albums.test").musicPage(
            .albums(library: "lib"),
            sort: MusicSort(.premiereDate, .descending),
            startIndex: 0,
            limit: 100,
            includeTotalCount: true,
        )

        let query = try #require(sent.request).query
        #expect(query["parentId"] == "lib")
        #expect(query["includeItemTypes"] == "MusicAlbum")
        #expect(query["recursive"] == "true")
        #expect(query["sortBy"] == "PremiereDate,SortName")
        #expect(query["sortOrder"] == "Descending,Ascending")
        #expect(query["startIndex"] == "0")
        #expect(query["limit"] == "100")
        #expect(query["enableTotalRecordCount"] == "true")
        #expect(page.totalCount == 4)
        let album = try #require(page.items.first)
        #expect(album.item.kind == .musicAlbum)
        #expect(album.subtitle == "Leap Fidei - 2024")
        #expect(album.albumArtistLinks == [MusicArtistLink(id: "ar1", name: "Leap Fidei")])
        #expect(album.details.userState.isFavorite)
        #expect(album.coverImage?.tag == "cover")
        #expect(album.songCount == 1)
    }

    @Test func `the artists tab asks for every artist in the library`() async throws {
        let sent = register(host: "music-artists.test", path: "/jf/Artists", reply: .json("""
        {"Items":[{"Id":"ar1","Name":"Binaerpilot","Type":"MusicArtist"}],"TotalRecordCount":1}
        """))

        let page = try await session(host: "music-artists.test")
            .musicPage(.artists(library: "lib"), sort: .default, startIndex: 100, limit: 50)

        let query = try #require(sent.request).query
        #expect(query["parentId"] == "lib")
        #expect(query["userId"] == "u1")
        #expect(query["sortBy"] == "SortName")
        #expect(query["sortOrder"] == "Ascending")
        #expect(query["startIndex"] == "100")
        #expect(query["limit"] == "50")
        #expect(page.items.map(\.item.kind) == [.musicArtist])
        #expect(page.totalCount == nil)
    }

    @Test func `the songs tab and a genre ask for their own types`() async throws {
        let sent = register(host: "music-songs.test", path: "/jf/Items", reply: .json(#"{"Items":[]}"#))
        let session = try session(host: "music-songs.test")

        _ = try await session.musicPage(.songs(library: "lib"), sort: MusicSort(.album), startIndex: 0, limit: 10)
        var query = try #require(sent.request).query
        #expect(query["includeItemTypes"] == "Audio")
        #expect(query["sortBy"] == "Album,SortName")

        _ = try await session.musicPage(.genre("g1", library: "lib"), sort: .default, startIndex: 0, limit: 10)
        query = try #require(sent.request).query
        #expect(query["includeItemTypes"] == "MusicAlbum")
        #expect(query["genreIds"] == "g1")
        #expect(query["parentId"] == "lib")
    }

    @Test func `recommended rows ask as Wholphin's RecommendedMusic does`() async throws {
        let sent = register(host: "music-recommended.test", path: "/jf/Items", reply: .json(#"{"Items":[]}"#))
        let session = try session(host: "music-recommended.test")
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        _ = try await session.recommendedAlbums(.recentlyReleased, in: "lib", limit: 25, now: now)
        var query = try #require(sent.request).query
        #expect(query["sortBy"] == "PremiereDate,SortName")
        #expect(query["sortOrder"] == "Descending,Ascending")
        #expect(query["maxPremiereDate"]?.hasPrefix("2027-01-15") == true)
        #expect(query["limit"] == "25")
        #expect(query["includeItemTypes"] == "MusicAlbum")

        _ = try await session.recommendedAlbums(.recentlyAdded, in: "lib", limit: 25)
        query = try #require(sent.request).query
        #expect(query["sortBy"] == "DateCreated")
        #expect(query["sortOrder"] == "Descending")

        _ = try await session.recommendedAlbums(.topRated, in: "lib", limit: 25)
        query = try #require(sent.request).query
        #expect(query["sortBy"] == "CommunityRating")
    }

    @Test func `a song comes with its album, artists, track and streams`() async throws {
        _ = register(host: "music-song.test", path: "/jf/Items", reply: .json("""
        {"Items":[\(Self.song)],"TotalRecordCount":1}
        """))

        let song = try #require(try await session(host: "music-song.test").songs(onAlbum: "al1").first)

        #expect(song.item.kind == .audio)
        #expect(song.albumName == "Nemesis")
        #expect(song.albumID == "al1")
        #expect(song.coverImage == ItemImage(itemID: "al1", kind: .primary, tag: "cover"))
        #expect(song.artistNames == "Leap Fidei, Guest")
        #expect(song.subtitle == "Nemesis - Leap Fidei, Guest")
        #expect(song.trackNumber == 3)
        #expect(song.discNumber == 1)
        #expect(song.hasLyrics)
        #expect(song.audioStreams == [AudioStreamInfo(codec: "flac", channels: 6)])
        #expect(song.item.runtime == .seconds(180))
    }

    @Test func `songs to queue come in Wholphin's order for each source`() async throws {
        let sent = register(
            host: "music-queue.test",
            path: "/jf/Items",
            reply: .json(#"{"Items":[],"TotalRecordCount":0}"#),
        )
        let session = try session(host: "music-queue.test")

        _ = try await session.songs(from: .album("al1"), startIndex: 0, limit: nil)
        var query = try #require(sent.request).query
        #expect(query["parentId"] == "al1")
        #expect(query["sortBy"] == "ParentIndexNumber,IndexNumber,SortName")
        #expect(query["includeItemTypes"] == "Audio")
        #expect(query["fields"]?.contains("MediaStreams") == true)
        #expect(query["limit"] == nil)

        _ = try await session.songs(from: .artist("ar1"), startIndex: 100, limit: 100)
        query = try #require(sent.request).query
        #expect(query["artistIds"] == "ar1")
        #expect(query["recursive"] == "true")
        #expect(query["startIndex"] == "100")
        #expect(query["enableTotalRecordCount"] == "false")

        _ = try await session.songs(from: .library("lib"), shuffled: true, startIndex: 0, limit: 500)
        query = try #require(sent.request).query
        #expect(query["parentId"] == "lib")
        #expect(query["sortBy"] == "Random")

        // An album is shuffled here, not by the server, so turning shuffle off restores its order.
        _ = try await session.songs(from: .album("al1"), shuffled: true, startIndex: 0, limit: nil)
        query = try #require(sent.request).query
        #expect(query["sortBy"] == "ParentIndexNumber,IndexNumber,SortName")
    }

    @Test func `an artist's page rows ask as Wholphin's artist page does`() async throws {
        let sent = register(host: "music-artist.test", path: "/jf/Items", reply: .json(#"{"Items":[]}"#))
        let session = try session(host: "music-artist.test")

        _ = try await session.albums(byArtist: "ar1")
        var query = try #require(sent.request).query
        #expect(query["albumArtistIds"] == "ar1")
        #expect(query["includeItemTypes"] == "MusicAlbum")
        #expect(query["sortBy"] == "PremiereDate,SortName")

        _ = try await session.albums(featuringArtist: "ar1")
        query = try #require(sent.request).query
        #expect(query["contributingArtistIds"] == "ar1")

        _ = try await session.popularSongs(byArtist: "ar1")
        query = try #require(sent.request).query
        #expect(query["artistIds"] == "ar1")
        #expect(query["minCommunityRating"] == "1.0")
        #expect(query["sortBy"] == "CommunityRating")
        #expect(query["limit"] == "10")
    }

    @Test func `similar music leaves out the artists' own work`() async throws {
        let sent = register(host: "music-similar.test", path: "/jf/Items/al1/Similar", reply: .json(#"{"Items":[]}"#))

        _ = try await session(host: "music-similar.test").similarMusic(to: "al1", excludingArtists: ["ar1"])

        let query = try #require(sent.request).query
        #expect(query["excludeArtistIds"] == "ar1")
        #expect(query["limit"] == "25")
    }

    @Test func `an instant mix asks for up to 200 songs`() async throws {
        let sent = register(host: "music-mix.test", path: "/jf/Items/al1/InstantMix", reply: .json("""
        {"Items":[\(Self.song)]}
        """))

        let songs = try await session(host: "music-mix.test").instantMix(from: "al1")

        let query = try #require(sent.request).query
        #expect(query["limit"] == "200")
        #expect(query["userId"] == "u1")
        #expect(songs.map(\.id) == ["s1"])
    }

    @Test func `genres come with a cover from one of their albums`() async throws {
        let sent = Recorder()
        MockServer.register(host: "music-genres.test") { request in
            switch request.url?.path() {
            case "/jf/Genres":
                sent.last.withLock { $0 = SentRequest(request) }
                return .json(#"{"Items":[{"Id":"g1","Name":"Electronic"},{"Id":"g2","Name":"Rock"}]}"#)
            case "/jf/Items":
                let genre = request.url?.queryValues["genreIds"]
                return genre == "g1" ? .json("{\"Items\":[\(Self.album)]}") : .json(#"{"Items":[]}"#)
            default:
                return nil
            }
        }

        let genres = try await session(host: "music-genres.test").musicGenres(in: "lib")

        let query = try #require(sent.request).query
        #expect(query["parentId"] == "lib")
        #expect(query["includeItemTypes"] == "MusicAlbum")
        #expect(genres.map(\.name) == ["Electronic", "Rock"])
        #expect(genres.map(\.image?.tag) == ["cover", nil])
    }

    @Test func `a song streams through the universal endpoint with the token in the query`() throws {
        let session = try session(host: "music-stream.test")
        let song = MusicItem(details: ItemDetails(item: MediaItem(id: "s1", name: "Song", kind: .audio)))

        let direct = try #require(session.audioStream(for: song))
        #expect(direct.method == .directPlay)
        #expect(direct.url.path() == "/jf/Audio/s1/universal")
        var query = direct.url.queryValues
        #expect(query["container"]?.contains("flac") == true)
        #expect(query["container"]?.contains("m4a|alac") == true)
        #expect(query["userId"] == "u1")
        #expect(query["deviceId"] == "device-1")
        #expect(query["ApiKey"] == "tok")

        let transcode = try #require(session.audioStream(for: song, allowsDirect: false))
        #expect(transcode.method == .transcode)
        query = transcode.url.queryValues
        #expect(query["container"] == nil)
        #expect(query["ApiKey"] == "tok")
    }

    @Test func `surround songs take the AC3 transcode in a container AVPlayer plays`() throws {
        var song = MusicItem(details: ItemDetails(item: MediaItem(id: "s1", name: "Song", kind: .audio)))
        song.audioStreams = [AudioStreamInfo(codec: "flac", channels: 6)]

        let stream = try #require(session(host: "music-ac3.test").audioStream(for: song, prefersAC3Surround: true))

        #expect(stream.method == .transcode)
        let query = stream.url.queryValues
        #expect(query["audioCodec"] == "ac3")
        #expect(query["maxAudioChannels"] == "6")
        #expect(query["transcodingAudioChannels"] == "6")
        #expect(query["transcodingContainer"] == "mp4")
        #expect(query["transcodingProtocol"] == "hls")
    }

    @Test func `a revoked token signs the user out`() async throws {
        MockServer.register(host: "music-revoked.test") { _ in .unauthorized }

        await #expect(throws: SessionError.signedOut) {
            try await session(host: "music-revoked.test").musicItem(id: "al1")
        }
    }
}

/// Queues from the Songs tab, which follow the tab's sort.
extension MusicTests {
    @Test func `the songs tab's songs queue in the tab's sort`() async throws {
        let sent = register(
            host: "music-songs-queue.test",
            path: "/jf/Items",
            reply: .json(#"{"Items":[],"TotalRecordCount":0}"#),
        )
        let session = try session(host: "music-songs-queue.test")

        let byAlbum = MusicSource.songs(library: "lib", sort: MusicSort(.album, .descending))
        _ = try await session.songs(from: byAlbum, startIndex: 0, limit: 100)
        var query = try #require(sent.request).query
        #expect(query["parentId"] == "lib")
        #expect(query["recursive"] == "true")
        #expect(query["includeItemTypes"] == "Audio")
        #expect(query["sortBy"] == "Album,SortName")
        #expect(query["sortOrder"] == "Descending,Ascending")
        #expect(!byAlbum.isRandomOrder)

        _ = try await session.songs(from: byAlbum, shuffled: true, startIndex: 0, limit: 500)
        query = try #require(sent.request).query
        #expect(query["sortBy"] == "Random")
        #expect(query["sortOrder"] == nil)

        #expect(MusicSource.songs(library: "lib", sort: MusicSort(.random)).isRandomOrder)
    }
}
