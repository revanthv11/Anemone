@testable import AnemoneJellyfin
import Foundation
import JellyfinAPI
import Testing

/// Trickplay and chapters for the player's overlay: finding a thumbnail, choosing from the
/// manifest, and the requests.
struct TrickplayTests {
    /// Jellyfin's defaults: 320 px thumbnails every 10 s, 10 × 10 to a sheet.
    private let trickplay = Trickplay(
        itemID: "m1",
        mediaSourceID: "src1",
        width: 320,
        height: 180,
        columns: 10,
        rows: 10,
        thumbnailCount: 558,
        interval: .seconds(10),
    )

    private func session(host: String) throws -> JellyfinSession {
        try JellyfinSession(
            serverURL: #require(URL(string: "https://\(host)")),
            userID: "u1",
            accessToken: "tok",
            identity: ClientIdentity(deviceName: "Test TV", deviceID: "device-1", appVersion: "0.1.0"),
            sessionConfiguration: { MockServer.sessionConfiguration() },
        )
    }

    /// Answers requests for `path` with `reply`, recording the last one and its path.
    private func register(host: String, path: String, reply: MockServer.Reply) -> Recorder {
        let recorder = Recorder()
        MockServer.register(host: host) { request in
            guard request.url?.path() == path else { return nil }
            recorder.last.withLock { $0 = SentRequest(request) }
            return reply
        }
        return recorder
    }

    @Test func `finds the thumbnail for a position, one per interval`() {
        #expect(trickplay.tile(at: .zero) == .init(sheet: 0, column: 0, row: 0))
        #expect(trickplay.tile(at: .seconds(15)) == .init(sheet: 0, column: 1, row: 0))
        #expect(trickplay.tile(at: .seconds(125)) == .init(sheet: 0, column: 2, row: 1))
        #expect(trickplay.tile(at: .seconds(999)) == .init(sheet: 0, column: 9, row: 9))
        #expect(trickplay.tile(at: .seconds(1000)) == .init(sheet: 1, column: 0, row: 0))
    }

    @Test func `stays on the first and last thumbnails outside the video`() {
        #expect(trickplay.tile(at: .seconds(-5)) == .init(sheet: 0, column: 0, row: 0))
        // Thumbnail 557 is the last: sheet 5, cell 57.
        #expect(trickplay.tile(at: .seconds(5570)) == .init(sheet: 5, column: 7, row: 5))
        #expect(trickplay.tile(at: .seconds(9000)) == .init(sheet: 5, column: 7, row: 5))
        #expect(trickplay.sheetCount == 6)
    }

    @Test func `picks the playing version at the widest width up to 480`() throws {
        let manifest = [
            "src1": ["320": Self.info(width: 320), "640": Self.info(width: 640), "480": Self.info(width: 480)],
            "src2": ["320": Self.info(width: 320)],
        ]

        let chosen = try #require(Trickplay(itemID: "m1", manifest: manifest, mediaSourceID: "src1"))

        #expect(chosen.mediaSourceID == "src1")
        #expect(chosen.width == 480)
        #expect(chosen.height == 270)
        #expect(chosen.interval == .seconds(10))
        #expect(chosen.thumbnailCount == 558)
    }

    @Test func `takes the narrowest width when every width is wider`() throws {
        let manifest = ["src1": ["1280": Self.info(width: 1280), "640": Self.info(width: 640)]]

        let chosen = try #require(Trickplay(itemID: "m1", manifest: manifest, mediaSourceID: "src1"))

        #expect(chosen.width == 640)
    }

    @Test func `falls back to another version when the playing one has no thumbnails`() throws {
        let manifest = ["b": ["320": Self.info(width: 320)], "a": [:]]

        let chosen = try #require(Trickplay(itemID: "m1", manifest: manifest, mediaSourceID: "c"))

        #expect(chosen.mediaSourceID == "b")
        #expect(Trickplay(itemID: "m1", manifest: [:], mediaSourceID: nil) == nil)
        let incomplete = ["a": ["320": TrickplayInfoDto(width: 320)]]
        #expect(Trickplay(itemID: "m1", manifest: incomplete, mediaSourceID: nil) == nil)
    }

    @Test func `asks for just chapters and trickplay, and maps them`() async throws {
        let sent = register(host: "previews.test", path: "/Items", reply: .json(#"""
        {"Items":[{"Id":"m1","Name":"Film","Type":"Movie",
          "Chapters":[
            {"Name":"Ending","StartPositionTicks":30000000000,"ImageTag":"t2"},
            {"Name":"Opening","StartPositionTicks":0,"ImageTag":"t0"},
            {"Name":" ","StartPositionTicks":6000000000}
          ],
          "Trickplay":{"src1":{"320":{"Width":320,"Height":180,"TileWidth":10,"TileHeight":10,
                                       "ThumbnailCount":558,"Interval":10000,"Bandwidth":1000}}}}],
         "TotalRecordCount":1}
        """#))

        let previews = try await session(host: "previews.test").seekPreviews(for: "m1", mediaSourceID: "src1")

        let query = try #require(sent.request?.query)
        #expect(query["ids"] == "m1")
        #expect(query["fields"] == "Chapters,Trickplay")
        #expect(query["userId"] == "u1")
        #expect(previews.chapters == [
            Chapter(index: 1, name: "Opening", start: .zero, imageTag: "t0"),
            Chapter(index: 2, name: nil, start: .seconds(600)),
            Chapter(index: 0, name: "Ending", start: .seconds(3000), imageTag: "t2"),
        ])
        #expect(previews.trickplay == trickplay)
    }

    @Test func `an item without them has no previews`() async throws {
        _ = register(host: "plain.test", path: "/Items", reply: .json(#"""
        {"Items":[{"Id":"m1","Name":"Film","Type":"Movie"}],"TotalRecordCount":1}
        """#))

        let previews = try await session(host: "plain.test").seekPreviews(for: "m1", mediaSourceID: nil)

        #expect(previews == SeekPreviews())
    }

    @Test func `fetches a sheet of thumbnails with the token in the header`() async throws {
        let headers = Recorder()
        MockServer.register(host: "sheet.test") { request in
            guard request.url?.path() == "/Videos/m1/Trickplay/320/2.jpg" else { return nil }
            headers.last.withLock { $0 = SentRequest(request) }
            #expect(request.value(forHTTPHeaderField: "Authorization")?.contains("Token=tok") == true)
            return MockServer.Reply(status: 200, body: "jpeg bytes")
        }

        let data = try await session(host: "sheet.test").trickplaySheet(2, of: trickplay)

        #expect(data == Data("jpeg bytes".utf8))
        #expect(headers.request?.query["mediaSourceId"] == "src1")
        #expect(headers.request?.query["ApiKey"] == nil)
    }

    @Test func `keeps only the sheets asked for last`() {
        var recent = Trickplay.RecentSheets(limit: 3)

        #expect(recent.ask(for: 0) == [])
        #expect(recent.ask(for: 1) == [])
        #expect(recent.ask(for: 2) == [])
        // Asked again, 0 is the latest, so 1 goes first.
        #expect(recent.ask(for: 0) == [])
        #expect(recent.ask(for: 5) == [1])
        #expect(recent.sheets == [2, 0, 5])
    }

    @Test func `a sheet that loads after seeking moved on isn't wanted`() {
        var recent = Trickplay.RecentSheets(limit: 3)
        _ = recent.ask(for: 0)

        // A fast hold passes several sheets while sheet 0 is still loading.
        for sheet in 1 ... 6 {
            _ = recent.ask(for: sheet)
        }

        #expect(!recent.wants(0))
        #expect(recent.wants(6))
        #expect(recent.sheets.count == 3)
    }

    @Test func `points at a chapter's image by its index`() throws {
        let session = try session(host: "images.test")
        let chapter = Chapter(index: 3, name: "Act Two", start: .seconds(60), imageTag: "abc")

        let url = try #require(session.chapterImageURL(chapter, of: "m1", maxWidth: 400))

        #expect(url.path() == "/Items/m1/Images/Chapter/3")
        #expect(url.queryValues == ["tag": "abc", "maxWidth": "400", "quality": "96"])
        #expect(session.chapterImageURL(Chapter(index: 0, name: nil, start: .zero), of: "m1", maxWidth: 400) == nil)
    }

    @Test func `finds the chapter playing, or the first before them all`() {
        // In playing order, with the server's indices, which needn't follow it.
        let chapters = [
            Chapter(index: 1, name: "A", start: .seconds(10)),
            Chapter(index: 2, name: "B", start: .seconds(60)),
            Chapter(index: 0, name: "C", start: .seconds(120)),
        ]

        #expect(chapters.chapter(at: .zero)?.name == "A")
        #expect(chapters.chapter(at: .seconds(59))?.name == "A")
        #expect(chapters.chapter(at: .seconds(60))?.name == "B")
        #expect(chapters.chapter(at: .seconds(5000))?.id == 0)
        #expect([Chapter]().chapter(at: .seconds(5)) == nil)
    }

    private static func info(width: Int) -> TrickplayInfoDto {
        TrickplayInfoDto(
            bandwidth: 1000,
            height: width * 9 / 16,
            interval: 10000,
            thumbnailCount: 558,
            tileHeight: 10,
            tileWidth: 10,
            width: width,
        )
    }
}
