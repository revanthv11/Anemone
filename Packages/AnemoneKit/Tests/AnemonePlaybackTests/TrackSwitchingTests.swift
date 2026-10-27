import AnemoneCore
import AnemoneJellyfin
@testable import AnemonePlayback
import Foundation
import JellyfinAPI
import Synchronization
import Testing

/// Whether a switch happens in the stream that's playing.
struct TrackSwitchingTests {
    private let hls = PlaybackStream.hls("m1", TrackRequest(audioIndex: 1, subtitleIndex: 4), method: .directStream)
    private let playlistSubtitles = (0 ..< 4).map {
        PlayerTrack(id: $0, kind: .subtitle, title: "Subtitle \($0)", language: "en", isSelected: $0 == 0)
    }

    private func track(_ index: Int) throws -> MediaTrack {
        try #require(hls.tracks.first { $0.index == index })
    }

    @Test func `HLS carries one audio track, so audio takes another stream`() throws {
        let options = [PlayerTrack(id: 0, kind: .audio, title: "English", language: "en", isSelected: true)]

        #expect(try TrackSwitching.audio(track(2), in: hls, options: options) == .reload)
        #expect(try TrackSwitching.playerTrack(for: track(1), in: hls, options: options) == options.first)
    }

    @Test func `HLS lists every text subtitle, in order`() throws {
        #expect(TrackSwitching.listed(.subtitle, in: hls).map(\.index) == [4, 5, 6, 7])
        #expect(try TrackSwitching.subtitle(
            from: track(4),
            to: track(5),
            in: hls,
            options: playlistSubtitles,
            burnsInStyled: true,
        ) == .inPlace(playlistSubtitles[1]))
        #expect(try TrackSwitching.subtitle(
            from: track(4),
            to: nil,
            in: hls,
            options: playlistSubtitles,
            burnsInStyled: true,
        )
            == .inPlace(nil))
    }

    @Test func `picture subtitles and, on AVPlayer, ASS are burned in`() throws {
        #expect(try TrackSwitching.subtitle(
            from: nil,
            to: track(8),
            in: hls,
            options: playlistSubtitles,
            burnsInStyled: true,
        )
            == .reload)
        #expect(try TrackSwitching.subtitle(
            from: nil,
            to: track(7),
            in: hls,
            options: playlistSubtitles,
            burnsInStyled: true,
        )
            == .reload)
        #expect(try TrackSwitching.subtitle(
            from: nil,
            to: track(7),
            in: hls,
            options: playlistSubtitles,
            burnsInStyled: false,
        )
            == .inPlace(playlistSubtitles[3]))
    }

    @Test func `the playlist lists ASS even when the server would only burn it in`() throws {
        // What Jellyfin 12.3 answered for the fixture's multi-track file.
        let tracks = hls.tracks.map { track in
            var track = track
            if track.isStyledText {
                track.delivery = .burnedIn
            }
            return track
        }
        let stream = PlaybackStream(
            itemID: "m1",
            url: hls.url,
            method: .transcode,
            audioStreamIndex: 1,
            subtitleStreamIndex: 4,
            tracks: tracks,
        )

        #expect(TrackSwitching.listed(.subtitle, in: stream).map(\.index) == [4, 5, 6, 7])
        #expect(try TrackSwitching.playerTrack(for: track(6), in: stream, options: playlistSubtitles)
            == playlistSubtitles[2])
        #expect(try TrackSwitching.subtitle(
            from: track(4),
            to: track(7),
            in: stream,
            options: playlistSubtitles,
            burnsInStyled: false,
        ) == .reload)
    }

    @Test func `a stream with burned-in subtitles lists none`() throws {
        let burned = PlaybackStream.hls("m1", TrackRequest(audioIndex: 1, subtitleIndex: 8), method: .transcode)

        #expect(TrackSwitching.listed(.subtitle, in: burned).isEmpty)
        #expect(try TrackSwitching
            .subtitle(from: track(8), to: nil, in: burned, options: [], burnsInStyled: true) == .reload)
    }

    @Test func `without matching counts, a track is found by name`() throws {
        let options = [
            PlayerTrack(id: 0, kind: .subtitle, title: "English - SUBRIP", language: "en", isSelected: false),
            PlayerTrack(id: 1, kind: .subtitle, title: "English SDH - SUBRIP", language: "en", isSelected: false),
        ]

        #expect(try TrackSwitching.playerTrack(for: track(6), in: hls, options: options) == options[1])
        #expect(try TrackSwitching.playerTrack(for: track(7), in: hls, options: options) == nil)
    }

    @Test func `a request without burned-in subtitles keeps the profile`() {
        let profile = DeviceProfile(name: "Test", subtitleProfiles: [SubtitleProfile(format: "vtt", method: .hls)])

        #expect(TrackRequest(subtitleIndex: 4).profile(from: profile) == profile)
        #expect(TrackRequest(subtitleIndex: 7).subtitleStreamIndex == 7)
        #expect(TrackRequest().subtitleStreamIndex == -1)
    }
}

/// Reloading the entry for another stream.
@MainActor
struct PlaybackReloadTests {
    @Test func `a reload ends the session and plays on from the same position`() async {
        let engine = TrackEngine()
        let log = EventLog()
        let streams = FakeStreams()
        let playback = PlaybackController(
            request: PlaybackRequest(.item("m1", from: .seconds(5))),
            engine: engine,
            features: [log],
            loadStream: streams.load,
        )
        await playback.start()
        engine.send(.ready)
        _ = await eventually { log.events.contains { $0.hasPrefix("started") } }
        engine.currentTime = .seconds(30)

        playback.reload()

        #expect(await eventually { log.events.contains { $0.hasPrefix("reloaded") } })
        #expect(engine.loads.last?.position == .seconds(30))
        #expect(streams.received.last == .init(itemID: "m1", allowsDirect: true, mediaSourceID: "src-m1"))
        #expect(log.events.after("stopped 30.0 seconds") == ["reloaded m1 directPlay"])
    }

    @Test func `a reload before the stream is ready plays on from where it was to start`() async {
        let engine = FakeEngine()
        let playback = PlaybackController(
            request: PlaybackRequest(.item("m1", from: .seconds(300))),
            engine: engine,
            features: [],
            loadStream: FakeStreams().load,
        )
        await playback.start()

        // The engine says 0 until it's ready at the resume position, as AVPlayer does.
        playback.reload()
        #expect(await eventually { engine.loads.count == 2 })
        // And again, before the new stream is ready.
        playback.reload()
        #expect(await eventually { engine.loads.count == 3 })

        #expect(engine.loads.map(\.position) == [.seconds(300), .seconds(300), .seconds(300)])
    }

    @Test func `features have a say in each request for a stream`() async {
        let engine = FakeEngine()
        let picker = AudioPicker()
        let requests = StreamRequestLog()
        let playback = PlaybackController(
            request: PlaybackRequest(.item("m1")),
            engine: engine,
            features: [picker],
        ) { request in
            requests.append(request)
            return FakeStreams.stream(request.itemID, method: .directPlay)
        }
        await playback.start()
        picker.audioIndex = 2

        playback.reload()

        #expect(await eventually { requests.sent.count == 2 })
        #expect(requests.sent.map(\.audioStreamIndex) == [1, 2])
        #expect(requests.sent.map(\.mediaSourceID) == [nil, "src-m1"])
        #expect(requests.sent.first?.profile == engine.deviceProfile)
    }

    @Test func `a reload keeps the overlay's previews and takes the new stream`() async {
        let engine = FakeEngine()
        let fetches = Mutex(0)
        let details = PlaybackDetails { _, _ in
            fetches.withLock { $0 += 1 }
            return SeekPreviews()
        }
        let loads = Mutex(0)
        let playback = PlaybackController(
            request: PlaybackRequest(.item("m1")),
            engine: engine,
            features: [details],
        ) { request in
            // The reload gets a remux, to tell the streams apart.
            let count = loads.withLock { $0 += 1; return $0 }
            return FakeStreams.stream(request.itemID, method: count == 1 ? .directPlay : .directStream)
        }
        await playback.start()
        details.loadSeekPreviews()
        _ = await eventually { details.previews != nil }

        playback.reload()

        #expect(await eventually { details.stream?.method == .directStream })
        #expect(details.previews != nil)
        #expect(fetches.withLock(\.self) == 1)
    }

    @Test func `a reload keeps what Up Next and segment skipping did for the entry`() async throws {
        let engine = FakeEngine()
        let log = EventLog()
        let intro = MediaSegment(id: "intro", kind: .intro, start: .seconds(10), end: .seconds(40))
        let outro = MediaSegment(id: "outro", kind: .outro, start: .seconds(80), end: .seconds(100))
        let segments = SegmentSkipping(
            load: { _ in [intro, outro] },
            offerDuration: .milliseconds(300),
            behavior: { $0 == .intro ? .ask : .ignore },
        )
        let upNext = UpNext(
            settings: UpNext.Settings(
                autoplays: true,
                countdown: .seconds(100),
                timing: .duringCredits,
                passOutCount: 0,
                stillWatchingTimeout: .seconds(5),
                testCreditsStart: nil,
            ),
            second: .milliseconds(10),
        )
        let playback = try PlaybackController(
            request: PlaybackRequest(queue: #require(PlaybackQueue(entries: [.item("e1"), .item("e2")]))),
            engine: engine,
            features: [segments, log, upNext],
            positionInterval: .milliseconds(10),
            loadStream: FakeStreams().load,
        )
        func reload(_ count: Int) async {
            playback.reload()
            _ = await eventually { engine.loads.count == count }
            engine.send(.ready)
            _ = await eventually { log.events.count { $0.hasPrefix("started") } == count }
            try? await Task.sleep(for: .milliseconds(50))
        }
        await playback.start()
        engine.send(.ready)
        #expect(await eventually { !segments.segments.isEmpty })

        // The intro's skip button comes and goes, and doesn't come back after a reload.
        engine.currentTime = .seconds(12)
        #expect(await eventually { !playback.accessories.actions.isEmpty })
        #expect(await eventually { playback.accessories.actions.isEmpty })
        await reload(2)
        #expect(log.events.after("stopped 12.0 seconds").first == "reloaded e1 directPlay")
        #expect(playback.accessories.actions.isEmpty)

        // Up Next comes with the credits and is cancelled, and stays cancelled after a reload.
        engine.currentTime = .seconds(85)
        #expect(await eventually { playback.accessories.card?.id == UpNext.upNextCard })
        try #require(playback.accessories.card?.actions.first { $0.id == "upNext.cancel" }).perform()
        await reload(3)
        #expect(engine.loads.last?.position == .seconds(85))
        #expect(playback.accessories.card == nil)
        await playback.stop()
    }
}

/// A feature that asks for an audio track.
@MainActor
private final class AudioPicker: PlaybackFeature {
    var audioIndex = 1

    func handle(_: PlaybackEvent, in _: PlaybackController) async {}

    func prepare(_ request: inout StreamRequest) async {
        request.audioStreamIndex = audioIndex
    }
}
