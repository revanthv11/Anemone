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

    @Test func `it's ready once its file has started and playback has restarted at its start`() async {
        let client = FakeMPVClient()
        let engine = MPVPlayerEngine.testing(client)
        _ = engine.loadLog()
        engine.handle(.startFile(entry: client.entries[0]))
        let log = engine.loadLog()

        // What libmpv says about the file this one replaced comes first, and doesn't count.
        engine.handle(.playbackRestart)
        engine.handle(.endFile(entry: client.entries[0], .failed("loading failed")))
        #expect(await eventually { log.events == ["paused"] })

        engine.handle(.startFile(entry: client.entries[1]))
        engine.handle(.playbackRestart)

        #expect(await eventually { log.events == ["paused", "ready", "paused"] })
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

    @Test func `a seek lands exactly when playback restarts, and a newer seek replaces it`() async {
        let client = FakeMPVClient()
        let engine = MPVPlayerEngine.testing(client)
        _ = engine.loadAndStart(on: client)

        let first = Task { await engine.seek(to: .seconds(30)) }
        #expect(await eventually { client.commands.count == 2 })
        let second = Task { await engine.seek(to: .seconds(45)) }
        #expect(await eventually { client.commands.count == 3 })
        engine.handle(.playbackRestart)

        #expect(await first.value == false)
        #expect(await second.value == true)
        #expect(client.commands.suffix(2) == [
            ["seek", "30.000", "absolute+exact"],
            ["seek", "45.000", "absolute+exact"],
        ])
    }

    @Test func `a seek waiting when the engine stops didn't get there`() async {
        let client = FakeMPVClient()
        let engine = MPVPlayerEngine.testing(client)
        _ = engine.loadAndStart(on: client)

        async let seek = engine.seek(to: .seconds(30))
        #expect(await eventually { client.commands.count == 2 })
        engine.stop()

        #expect(await seek == false)
        #expect(client.commands.last == ["stop"])
    }

    @Test func `there's no seeking before the file is ready`() async {
        let client = FakeMPVClient()
        let engine = MPVPlayerEngine.testing(client)
        _ = engine.load(URL(filePath: "/m.mkv"), from: nil, metadata: PlaybackMetadata(title: "M"))

        #expect(await engine.seek(to: .seconds(30)) == false)
        #expect(client.commands.count == 1)
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

    @Test func `subtitles from outside the file are added and shown`() throws {
        let client = FakeMPVClient()
        let engine = MPVPlayerEngine.testing(client)
        let url = try #require(URL(string: "https://jf.test/sub.srt"))

        engine.addSubtitles(from: url, title: "English", language: "eng")

        #expect(client.commands.last == ["sub-add", "https://jf.test/sub.srt", "select", "English", "eng"])
    }

    @Test func `languages without a two-letter code keep theirs`() {
        #expect(MPVTrackList.languageTag("ger") == "de")
        #expect(MPVTrackList.languageTag("chi") == "zh")
        #expect(MPVTrackList.languageTag("und") == "und")
    }
}
