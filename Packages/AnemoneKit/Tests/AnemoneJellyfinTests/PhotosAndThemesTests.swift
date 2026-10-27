import AnemoneJellyfin
import Foundation
import Synchronization
import Testing

/// Asking the fake server for theme songs, cinema intros and slideshow photos.
struct PhotosAndThemesTests {
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

    // MARK: Theme songs

    @Test func `an item's theme songs are asked for as the user`() async throws {
        let sent = register(host: "themes.test", path: "/jf/Items/m1/ThemeSongs", reply: .json("""
        {"Items":[{"Id":"song1","Name":"Theme","Type":"Audio"},{"Name":"No ID"}],"TotalRecordCount":2}
        """))

        let songs = try await session(host: "themes.test").themeSongs(of: "m1")

        let request = try #require(sent.request)
        #expect(request.method == "GET")
        #expect(request.query == ["userId": "u1"])
        #expect(songs == ["song1"])
    }

    @Test func `a theme song streams from the universal endpoint with the token in the URL`() throws {
        let url = try #require(try session(host: "theme-url.test").themeSongURL(for: "song1"))

        #expect(url.path() == "/jf/Audio/song1/universal")
        let query = url.queryValues
        #expect(query["container"] == "mp3,aac,m4a|aac,m4a|alac,mp4|aac,flac,wav")
        #expect(query["container"]?.contains("opus") == false)
        #expect(query["deviceId"] == "device-1")
        #expect(query["userId"] == "u1")
        #expect(query["ApiKey"] == "tok")
    }

    @Test func `an item without theme songs has no song to play`() async throws {
        _ = register(host: "no-themes.test", path: "/jf/Items/m1/ThemeSongs", reply: .json("""
        {"Items":[],"TotalRecordCount":0}
        """))

        let url = try await session(host: "no-themes.test").randomThemeSongURL(of: "m1")

        #expect(url == nil)
    }

    @Test func `the theme song played is one of the item's`() async throws {
        _ = register(host: "one-theme.test", path: "/jf/Items/s1/ThemeSongs", reply: .json("""
        {"Items":[{"Id":"song1"},{"Id":"song2"}]}
        """))

        let url = try #require(try await session(host: "one-theme.test").randomThemeSongURL(of: "s1"))

        #expect(["/jf/Audio/song1/universal", "/jf/Audio/song2/universal"].contains(url.path()))
    }

    // MARK: Intros

    @Test func `intros are asked for as the user, in the server's order`() async throws {
        let sent = register(host: "intros.test", path: "/jf/Items/m1/Intros", reply: .json("""
        {"Items":[
         {"Id":"i1","Name":"Anemone Pre-roll One","Type":"Video"},
         {"Id":"i2","Name":"Anemone Pre-roll Two","Type":"Video"}
        ],"TotalRecordCount":2}
        """))

        let intros = try await session(host: "intros.test").intros(for: "m1")

        let request = try #require(sent.request)
        #expect(request.method == "GET")
        #expect(request.query == ["userId": "u1"])
        #expect(intros.map(\.id) == ["i1", "i2"])
        #expect(intros.map(\.name) == ["Anemone Pre-roll One", "Anemone Pre-roll Two"])
    }

    @Test func `a server without intros has none`() async throws {
        _ = register(host: "no-intros.test", path: "/jf/Items/m1/Intros", reply: .json(#"{"Items":[]}"#))

        let intros = try await session(host: "no-intros.test").intros(for: "m1")

        #expect(intros.isEmpty)
    }

    // MARK: Slideshow

    @Test func `a slideshow asks for the album's photos in the grid's order`() async throws {
        let sent = register(host: "slideshow.test", path: "/jf/Items", reply: .json("""
        {"Items":[
         {"Id":"p1","Name":"Beach","Type":"Photo","ImageTags":{"Primary":"tag1"},"Width":4032,"Height":3024,
          "PremiereDate":"2025-07-14T10:00:00.0000000Z","Overview":"Low tide"},
         {"Id":"c1","Name":"Clip","Type":"Video","DateCreated":"2026-01-02T00:00:00.0000000Z"},
         {"Id":"a1","Name":"Album","Type":"PhotoAlbum"}
        ],"TotalRecordCount":17}
        """))
        let query = SlideshowQuery(folderID: "album1", sort: LibrarySort(.dateCreated, .descending))

        let page = try await session(host: "slideshow.test")
            .slideshowItems(query, startIndex: 100, limit: 50, includeTotalCount: true)

        let request = try #require(sent.request)
        #expect(request.query["parentId"] == "album1")
        #expect(request.query["includeItemTypes"] == "Photo")
        #expect(request.query["recursive"] == "false")
        #expect(request.query["sortBy"] == "DateCreated,SortName")
        #expect(request.query["sortOrder"] == "Descending,Ascending")
        #expect(request.query["startIndex"] == "100")
        #expect(request.query["limit"] == "50")
        #expect(request.query["enableTotalRecordCount"] == "true")
        #expect(request.query["fields"] == "Overview,Width,Height,DateCreated")
        #expect(page.totalCount == 17)
        // Only photos and clips; an album the server sent anyway is left out.
        #expect(page.items.map(\.id) == ["p1", "c1"])
        let photo = try #require(page.items.first)
        #expect(photo.kind == .photo)
        #expect(photo.image == ItemImage(itemID: "p1", kind: .primary, tag: "tag1"))
        #expect(photo.width == 4032)
        #expect(photo.height == 3024)
        #expect(photo.overview == "Low tide")
        #expect(photo.date == Date(timeIntervalSince1970: 1_752_487_200))
        #expect(page.items.last?.kind == .video)
        #expect(page.items.last?.date == Date(timeIntervalSince1970: 1_767_312_000))
    }

    @Test func `playing a folder shows the photos in its albums too, with clips when asked for`() async throws {
        let sent = register(host: "slideshow-all.test", path: "/jf/Items", reply: .json(#"{"Items":[]}"#))
        let query = SlideshowQuery(
            folderID: "lib1",
            sort: LibrarySort(.random),
            isRecursive: true,
            includesVideos: true,
        )

        _ = try await session(host: "slideshow-all.test").slideshowItems(query, startIndex: 0, limit: 100)

        let request = try #require(sent.request)
        #expect(request.query["includeItemTypes"] == "Photo,Video")
        #expect(request.query["recursive"] == "true")
        #expect(request.query["sortBy"] == "Random")
        #expect(request.query["enableTotalRecordCount"] == "false")
    }

    @Test func `a slideshow clip plays its file, with the token in the URL`() throws {
        let url = try #require(try session(host: "clip.test").slideshowClipURL(for: "c1"))

        #expect(url.path() == "/jf/Videos/c1/stream")
        #expect(url.queryValues["static"] == "true")
        #expect(url.queryValues["ApiKey"] == "tok")
    }
}
