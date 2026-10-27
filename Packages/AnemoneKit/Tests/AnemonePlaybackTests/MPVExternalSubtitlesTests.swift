import AnemoneJellyfin
@testable import AnemonePlayback
import Foundation
import Testing

/// Subtitle files beside the video, which the server delivers as External for MPV: added to
/// libmpv once the file opens, listed among the tracks, the server's default shown.
@MainActor
struct MPVExternalSubtitlesTests {
    private let french = ExternalSubtitle(url: URL(filePath: "/subs/fr.srt"), title: "French", language: "fre")
    private let english = ExternalSubtitle(
        url: URL(filePath: "/subs/en.ass"),
        title: "English - ASS - External",
        language: "eng",
        isDefault: true,
    )

    @Test func `subtitles beside the file are added once it opens, showing the server's default`() async {
        let client = FakeMPVClient()
        let engine = MPVPlayerEngine.testing(client)
        client.list([.init(type: "sub", id: 1, title: "Signs", lang: "eng", selected: true)])
        _ = engine.loadLog()

        engine.addExternalSubtitles([french, english], toStreamFrom: URL(filePath: "/m.mkv"))
        #expect(!client.commands.contains { $0.first == "sub-add" })
        engine.start(client.entries[0])

        #expect(client.commands.filter { $0.first == "sub-add" } == [
            ["sub-add", "file:///subs/fr.srt", "auto", "French", "fre"],
            ["sub-add", "file:///subs/en.ass", "select", "English - ASS - External", "eng"],
        ])
        let tracks = await engine.tracks(.subtitle)
        #expect(tracks.map(\.title) == ["Signs", "French", "English - ASS - External"])
        #expect(tracks.map(\.language) == ["en", "fr", "en"])
        #expect(tracks.map(\.isSelected) == [false, false, true])
    }

    @Test func `subtitles for a file that's open are added at once`() {
        let client = FakeMPVClient()
        let engine = MPVPlayerEngine.testing(client)
        _ = engine.loadAndStart(on: client)

        engine.addExternalSubtitles([french], toStreamFrom: URL(filePath: "/m.mkv"))

        #expect(client.commands.last == ["sub-add", "file:///subs/fr.srt", "auto", "French", "fre"])
    }

    @Test func `subtitles for a stream another has replaced aren't added`() {
        let client = FakeMPVClient()
        let engine = MPVPlayerEngine.testing(client)
        _ = engine.loadLog("/first.mkv")
        _ = engine.loadLog("/second.mkv")

        engine.addExternalSubtitles([french], toStreamFrom: URL(filePath: "/first.mkv"))
        engine.start(client.entries[1])

        #expect(!client.commands.contains { $0.first == "sub-add" })
    }

    @Test func `downloaded subtitles are added and shown`() throws {
        let client = FakeMPVClient()
        let engine = MPVPlayerEngine.testing(client)
        let url = try #require(URL(string: "https://jf.test/sub.srt"))

        engine.addSubtitles(from: url, title: "English", language: "eng")

        #expect(client.commands.last == ["sub-add", "https://jf.test/sub.srt", "select", "English", "eng"])
    }

    @Test func `while MPV plays, the server's subtitle files beside the video are added`() async throws {
        let host = "external-subs.test"
        StubServer.answer(host: host) { request in
            guard request.url?.path() == "/jf/Items/a" else { return nil }
            return #"{"Id":"a","Name":"A","Type":"Movie","MediaSources":[{"Id":"src-a","MediaStreams":["# +
                #"{"Index":0,"Type":"Video"},{"Index":2,"Type":"Subtitle","Codec":"ass"},"# +
                #"{"Index":3,"Type":"Subtitle","Codec":"subrip","Language":"eng","IsExternal":true,"# +
                #""DisplayTitle":"English - SUBRIP - External"},"# +
                #"{"Index":4,"Type":"Subtitle","Codec":"pgssub","IsExternal":true}]}]}"#
        }
        let client = FakeMPVClient()
        let engine = MPVPlayerEngine.testing(client)
        let controller = try PlaybackController(
            request: PlaybackRequest(.item("a")),
            engine: engine,
            features: [MPVExternalSubtitles(session: StubServer.session(host: host))],
            loadStream: FakeStreams().load,
        )

        await controller.start()
        engine.start(client.entries[0])

        #expect(await eventually { client.commands.last?.first == "sub-add" })
        let added = client.commands.filter { $0.first == "sub-add" }
        #expect(added.count == 1)
        #expect(added.first?[1].contains("/jf/Videos/a/src-a/Subtitles/3/Stream.subrip") == true)
        #expect(added.first?[1].contains("ApiKey=tok") == true)
        #expect(added.first.map { Array($0[2...]) } == ["auto", "English - SUBRIP - External", "eng"])
        await controller.stop()
    }

    @Test func `the files MPV asks for as External are text subtitles`() {
        #expect(MPVExternalSubtitles.formats == ["vtt", "webvtt", "srt", "subrip", "ttml", "ass", "ssa"])
    }
}
