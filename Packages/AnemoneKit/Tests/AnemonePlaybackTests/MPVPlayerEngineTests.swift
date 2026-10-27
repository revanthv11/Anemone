import AnemoneJellyfin
@testable import AnemonePlayback
import Foundation
import Testing

/// The MPV engine against a stand-in for libmpv: what it sets and runs, and how libmpv's events
/// become the engine's.
@MainActor
struct MPVPlayerEngineTests {
    @Test func `loading pauses, then loads the file at its start position with its title`() async throws {
        let client = FakeMPVClient()
        let engine = MPVPlayerEngine.testing(client)
        let url = try #require(URL(string: "https://jf.test/Videos/m1/stream?static=true&ApiKey=tok"))

        let log = PlayerEventLog(engine.load(
            url,
            from: .seconds(90.5),
            metadata: PlaybackMetadata(title: "Big, \"Buck\" Bunny"),
        ))

        #expect(client.lastSet("pause") == "yes")
        #expect(client.commands == [[
            "loadfile", "https://jf.test/Videos/m1/stream?static=true&ApiKey=tok", "replace", "-1",
            "force-media-title=%17%Big, \"Buck\" Bunny,start=90.500",
        ]])
        #expect(await eventually { log.events == ["paused"] })
    }

    @Test func `a load from the beginning has no start position`() {
        let client = FakeMPVClient()
        let engine = MPVPlayerEngine.testing(client)

        _ = engine.load(URL(filePath: "/m.mkv"), from: .zero, metadata: PlaybackMetadata(title: "M"))

        #expect(client.commands.last?.last == "force-media-title=%1%M")
    }

    @Test func `it's ready once playback of its own file has restarted at its start`() async throws {
        let client = FakeMPVClient()
        let engine = MPVPlayerEngine.testing(client)
        _ = engine.loadLog("/old.mkv")
        engine.handle(.startFile(entry: client.entries[0]))
        let log = engine.loadLog()
        let subtitles = try [ExternalSubtitle(url: #require(URL(string: "https://jf.test/sub.srt")), title: "English")]
        engine.addExternalSubtitles(subtitles, toStreamFrom: URL(filePath: "/m.mkv"))

        // What libmpv says about the file this one replaced, still on its way, doesn't count.
        engine.handle(.fileLoaded(entry: client.entries[0]))
        engine.handle(.playbackRestart(entry: client.entries[0]))
        engine.handle(.endFile(entry: client.entries[0], .stopped))
        #expect(await engine.seek(to: .seconds(5)) == false)
        #expect(!client.commands.contains { ["seek", "sub-add"].contains($0.first) })

        engine.start(client.entries[1])

        #expect(await eventually { log.events == ["paused", "ready", "paused"] })
        #expect(client.commands.last?.first == "sub-add")
    }

    /// libmpv always names the entry it made; if it ever doesn't, the load still plays.
    @Test func `a load libmpv took without naming its entry plays as the next entry to start`() async {
        let client = FakeMPVClient()
        let engine = MPVPlayerEngine.testing(client)
        _ = engine.loadAndStart(on: client)
        client.hidesEntries = true

        let log = engine.loadLog("/next.mkv")
        engine.handle(.playbackRestart(entry: client.entries[0]))
        engine.handle(.endFile(entry: client.entries[0], .stopped))
        engine.start(client.entries[1])
        engine.handle(.endFile(entry: client.entries[1], .failed("loading failed")))

        #expect(await eventually { log.isFinished })
        #expect(log.events == ["paused", "ready", "paused", "failed"])
    }

    @Test func `pausing, buffering and seeking set the status once it's ready`() async {
        let client = FakeMPVClient()
        let engine = MPVPlayerEngine.testing(client)
        let log = engine.loadAndStart(on: client)

        engine.play()
        #expect(client.lastSet("pause") == "no")
        engine.handle(.property("pause", .flag(false)))
        engine.handle(.property("paused-for-cache", .flag(true)))
        engine.handle(.property("paused-for-cache", .flag(false)))
        engine.handle(.property("seeking", .flag(true)))
        engine.handle(.property("seeking", .flag(false)))
        engine.handle(.property("pause", .flag(true)))

        #expect(await eventually {
            log.events == ["paused", "ready", "paused", "playing", "waiting", "playing", "waiting", "playing", "paused"]
        })
    }

    @Test func `the end of the file ends the stream once, keeping the last frame up`() async {
        let client = FakeMPVClient()
        let engine = MPVPlayerEngine.testing(client)
        let log = engine.loadAndStart(on: client)

        engine.handle(.property("eof-reached", .flag(true)))
        engine.handle(.property("eof-reached", .flag(true)))
        engine.handle(.endFile(entry: client.entries[0], .endOfFile))

        #expect(await eventually { log.events.last == "ended" })
        #expect(log.events.filter { $0 == "ended" }.count == 1)
    }

    /// A server error or a format libmpv doesn't know: libmpv starts the file and ends it with
    /// the error, without ever loading it or restarting playback.
    @Test func `a file that won't open fails with libmpv's reason`() async throws {
        let client = FakeMPVClient()
        let engine = MPVPlayerEngine.testing(client)
        let log = engine.loadLog()

        engine.handle(.startFile(entry: client.entries[0]))
        engine.handle(.endFile(entry: client.entries[0], .failed("unrecognized file format")))

        #expect(await eventually { log.isFinished })
        #expect(log.events == ["paused", "failed"])
        let error = try #require(log.errors.first as? PlayerError)
        guard case let .streamFailed(underlying) = error else {
            Issue.record("expected a stream failure, got \(error)")
            return
        }
        #expect(underlying as? MPVError == MPVError(reason: "unrecognized file format"))
    }

    @Test func `a file that fails while playing fails the stream`() async {
        let client = FakeMPVClient()
        let engine = MPVPlayerEngine.testing(client)
        let log = engine.loadAndStart(on: client)

        engine.handle(.endFile(entry: client.entries[0], .failed("loading failed")))

        #expect(await eventually { log.isFinished })
        #expect(log.events == ["paused", "ready", "paused", "failed"])
    }

    @Test func `a load libmpv refuses fails at once`() async throws {
        let client = FakeMPVClient()
        client.refusesLoads = true
        let engine = MPVPlayerEngine.testing(client)

        let log = engine.loadLog()

        #expect(await eventually { log.isFinished })
        #expect(log.events == ["failed"])
        let error = try #require(log.errors.first as? PlayerError)
        guard case let .streamFailed(underlying) = error else {
            Issue.record("expected a stream failure, got \(error)")
            return
        }
        #expect(underlying as? MPVError == .refused)
    }

    /// Wholphin's retry as a transcode, through the MPV engine: a direct play libmpv can't open
    /// gets another try as a transcode.
    @Test func `a direct play that won't open is retried as a transcode`() async {
        let client = FakeMPVClient()
        let engine = MPVPlayerEngine.testing(client)
        let streams = FakeStreams()
        let playback = PlaybackController(
            request: PlaybackRequest(.item("m1")),
            engine: engine,
            features: [],
            positionInterval: .milliseconds(10),
            loadStream: streams.load,
        )
        await playback.start()
        #expect(client.commands.last?[1] == FakeStreams.stream("m1", method: .directPlay).url.absoluteString)

        engine.handle(.startFile(entry: client.entries[0]))
        engine.handle(.endFile(entry: client.entries[0], .failed("loading failed")))

        #expect(await eventually { client.entries.count == 2 })
        #expect(streams.received.last?.allowsDirect == false)
        #expect(client.commands.last?[1] == FakeStreams.stream("m1", method: .transcode).url.absoluteString)
    }

    @Test func `without libmpv every load fails`() async {
        let engine = MPVPlayerEngine.testing(nil)

        let log = engine.loadLog()

        #expect(await eventually { log.isFinished })
        #expect(log.events == ["failed"])
    }

    @Test func `time and duration come from libmpv, keeping the last time once the file is gone`() {
        let client = FakeMPVClient()
        let engine = MPVPlayerEngine.testing(client)
        #expect(engine.duration == nil)

        client.properties["time-pos"] = "12.5"
        client.properties["duration"] = "600"
        #expect(engine.currentTime == .milliseconds(12500))
        #expect(engine.duration == .seconds(600))

        client.properties["time-pos"] = nil
        #expect(engine.currentTime == .milliseconds(12500))
    }

    @Test func `speed and subtitle delay go to libmpv`() {
        let client = FakeMPVClient()
        let engine = MPVPlayerEngine.testing(client)

        engine.rate = 1.5
        engine.subtitleDelay = .milliseconds(-500)

        #expect(engine.rate == 1.5)
        #expect(client.lastSet("speed") == "1.5")
        #expect(client.lastSet("sub-delay") == "-0.5")
    }

    @Test func `tracks are the file's of each kind, in its order, with BCP 47 languages`() async {
        let client = FakeMPVClient()
        let engine = MPVPlayerEngine.testing(client)
        client.list([
            .init(type: "video", id: 1, selected: true),
            .init(type: "audio", id: 1, title: "Stereo", lang: "eng", selected: true),
            .init(type: "audio", id: 2, lang: "fre"),
            .init(type: "sub", id: 1, title: "Signs", lang: "eng"),
            .init(type: "sub", id: 2, lang: "jpn", selected: true),
        ])

        let audio = await engine.tracks(.audio)
        let subtitles = await engine.tracks(.subtitle)

        #expect(audio.map(\.id) == [1, 2])
        #expect(audio.map(\.language) == ["en", "fr"])
        #expect(audio.map(\.isSelected) == [true, false])
        #expect(audio.first?.title == "Stereo")
        #expect(subtitles.map(\.id) == [1, 2])
        #expect(subtitles.map(\.language) == ["en", "ja"])
        #expect(subtitles.map(\.isSelected) == [false, true])
    }

    @Test func `choosing a track selects it by libmpv's ID, and no subtitles turns them off`() async {
        let client = FakeMPVClient()
        let engine = MPVPlayerEngine.testing(client)
        let french = PlayerTrack(id: 2, kind: .audio, title: "French", language: "fr", isSelected: false)

        await engine.select(french, .audio)
        await engine.select(nil, .subtitle)

        #expect(client.lastSet("aid") == "2")
        #expect(client.lastSet("sid") == "no")
    }

    @Test func `subtitles take the HDR style while HDR video plays`() {
        let client = FakeMPVClient()
        let engine = MPVPlayerEngine.testing(client)
        var hdr = SubtitleStyle()
        hdr.fontColor = .lightGray
        hdr.fontOpacity = 50

        engine.setSubtitleStyles(SubtitleStyles(standard: SubtitleStyle(), hdr: hdr))
        #expect(client.lastSet("sub-color") == "#FFFFFFFF")

        engine.handle(.property("video-params/gamma", .string("pq")))
        #expect(client.lastSet("sub-color") == "#80CCCCCC")

        engine.handle(.property("video-params/gamma", .string("bt.1886")))
        #expect(client.lastSet("sub-color") == "#FFFFFFFF")
    }

    @Test func `libmpv's messages are logged without tokens`() {
        let message = "Failed to open https://jf.test/Videos/m1/stream?static=true&ApiKey=tok123&Tag=x, "
            + "'https://jf.test/sub.srt?api_key=abc' and http://h/live?token=xyz"

        #expect(MPVLog.redacted(message) == "Failed to open https://jf.test/Videos/m1/stream?static=true&"
            + "ApiKey=<redacted>&Tag=x, 'https://jf.test/sub.srt?api_key=<redacted>' and "
            + "http://h/live?token=<redacted>")
        #expect(MPVLog.redacted("audio: AAC 2.0") == "audio: AAC 2.0")
    }

    @Test func `languages without a two-letter code keep theirs`() {
        #expect(MPVTrackList.languageTag("ger") == "de")
        #expect(MPVTrackList.languageTag("chi") == "zh")
        #expect(MPVTrackList.languageTag("und") == "und")
    }
}
