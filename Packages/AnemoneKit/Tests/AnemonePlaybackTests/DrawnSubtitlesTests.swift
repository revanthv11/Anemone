import AnemoneCore
import AnemoneJellyfin
@testable import AnemonePlayback
import Foundation
import JellyfinAPI
import Synchronization
import Testing

/// Text subtitles that come as files of their own: drawn by Anemone, switched without another
/// stream, shown at the playing position with the delay, alongside track selection.
@MainActor
struct DrawnSubtitlesTests {
    private let engine = TrackEngine()
    private let log = EventLog()
    private let requests = StreamRequestLog()
    private let fetches = SubtitleFetchLog()
    private let defaults: UserDefaults
    private let store: TrackChoiceStore

    init() throws {
        let suite = "DrawnSubtitlesTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        store = TrackChoiceStore(userID: "u1", defaults: defaults)
    }

    /// Subtitles whose files the fake server sends, after `delay` for the indices in `slow`;
    /// those in `failing` can't be fetched.
    private func drawn(failing: Set<Int> = [], slow: Set<Int> = [], delay: Duration = .zero) -> DrawnSubtitles {
        DrawnSubtitles(server: DrawnSubtitles.Server(timeline: { [fetches] request in
            fetches.append(request)
            if slow.contains(request.index) {
                try await Task.sleep(for: delay)
            }
            if failing.contains(request.index) {
                throw URLError(.badServerResponse)
            }
            return .numbered(request.index)
        }))
    }

    /// A player choosing tracks for the fixture's multi-track file, with a profile that likes
    /// English, and getting HLS back whose text subtitles come as files of their own.
    private func player(_ drawn: DrawnSubtitles) -> PlaybackController {
        let selection = TrackSelection(
            server: TrackSelection.Server(
                itemTracks: { ItemTracks(itemID: $0, sources: [.init(id: $0, tracks: .multiTrack)]) },
                profileSettings: { .english },
            ),
            store: store,
            defaults: defaults,
        )
        return PlaybackController(
            request: PlaybackRequest(.item("m1")),
            engine: engine,
            features: [drawn, selection, log],
            positionInterval: .milliseconds(10),
        ) { [requests] request in
            requests.append(request)
            return PlaybackStream.withSubtitleFiles(request.itemID, request.tracks)
        }
    }

    private func start(_ playback: PlaybackController) async {
        await playback.start()
        engine.send(.ready)
        _ = await eventually { log.events.contains { $0.hasPrefix("started") } }
    }

    private func pick(_ optionID: String, in menuID: String, of playback: PlaybackController) throws {
        let menu = playback.accessories.menus.first { $0.id == menuID }
        try #require(menu?.options.first { $0.id == optionID }).select()
    }

    /// Once the file has been read: the cues at `position`.
    private func cues(at position: Duration, in drawn: DrawnSubtitles) async -> [String] {
        _ = await eventually {
            drawn.update(at: position)
            return !drawn.cues.isEmpty
        }
        return drawn.cues.map(\.text)
    }

    @Test func `text subtitles are drawn from a file of their own and switch without another stream`() async throws {
        let drawn = drawn()
        let playback = player(drawn)
        await start(playback)

        // The default English SRT.
        #expect(requests.all == [TrackRequest(mediaSourceID: "m1", audioIndex: 1, subtitleIndex: 4)])
        #expect(await eventually { drawn.track?.index == 4 })
        #expect(fetches.all == [SubtitleFileRequest(itemID: "m1", mediaSourceID: "m1", index: 4, format: .srt)])
        #expect(await cues(at: .seconds(1), in: drawn) == ["Track 4 one"])

        try pick("subtitles.6", in: "subtitles", of: playback)
        #expect(await eventually { drawn.track?.index == 6 })
        #expect(await cues(at: .seconds(1), in: drawn) == ["Track 6 one"])
        try pick("subtitles.forced", in: "subtitles", of: playback)
        #expect(await eventually { drawn.track?.index == 5 })
        try pick("subtitles.off", in: "subtitles", of: playback)
        #expect(await eventually { drawn.track == nil })
        #expect(drawn.update(at: .seconds(1)) == nil)
        #expect(drawn.cues.isEmpty)

        #expect(engine.loads.count == 1)
        #expect(fetches.all.map(\.index) == [4, 6, 5])
        // The player has none of its own to show.
        #expect(engine.subtitleSelections.allSatisfy { $0 == nil })
    }

    @Test func `styled ASS and picture subtitles still take a stream with them burned in`() async throws {
        let drawn = drawn()
        let playback = player(drawn)
        await start(playback)
        #expect(await eventually { drawn.track?.index == 4 })

        try pick("subtitles.7", in: "subtitles", of: playback)
        #expect(await eventually { engine.loads.count == 2 })
        #expect(requests.all.last == TrackRequest(
            mediaSourceID: "m1",
            audioIndex: 1,
            subtitleIndex: 7,
            burnsInSubtitles: true,
        ))
        #expect(await eventually { log.events.contains { $0.hasPrefix("reloaded") } })
        #expect(drawn.track == nil)

        // Back to SRT takes a stream without the ASS; the file was read already.
        try pick("subtitles.4", in: "subtitles", of: playback)
        #expect(await eventually { engine.loads.count == 3 })
        #expect(await eventually { drawn.track?.index == 4 })
        #expect(await cues(at: .seconds(1), in: drawn) == ["Track 4 one"])
        #expect(fetches.all.map(\.index) == [4])

        try pick("subtitles.8", in: "subtitles", of: playback)
        #expect(await eventually { engine.loads.count == 4 })
        #expect(requests.all.last == TrackRequest(mediaSourceID: "m1", audioIndex: 1, subtitleIndex: 8))
        #expect(await eventually { drawn.track == nil })
    }

    @Test func `a reload for another audio track keeps the subtitles without fetching them again`() async throws {
        let drawn = drawn()
        let playback = player(drawn)
        await start(playback)
        #expect(await cues(at: .seconds(1), in: drawn) == ["Track 4 one"])

        try pick("audio.2", in: "audio", of: playback)

        #expect(await eventually { log.events.contains { $0.hasPrefix("reloaded") } })
        #expect(requests.all.last == TrackRequest(mediaSourceID: "m1", audioIndex: 2, subtitleIndex: 4))
        #expect(await eventually { drawn.track?.index == 4 })
        #expect(await cues(at: .seconds(1), in: drawn) == ["Track 4 one"])
        #expect(fetches.all.count == 1)
    }

    @Test func `what shows follows the position, after a seek too, shifted by the delay`() async throws {
        let drawn = drawn()
        let playback = player(drawn)
        await start(playback)
        #expect(await cues(at: .seconds(1), in: drawn) == ["Track 4 one"])

        // It ends at 2 s.
        #expect(drawn.update(at: .seconds(1)) == .seconds(1))
        // Nothing until 5 s.
        #expect(drawn.update(at: .seconds(3)) == .seconds(2))
        #expect(drawn.cues.isEmpty)
        // A sign over the dialogue, which ends first.
        #expect(drawn.update(at: .milliseconds(6500)) == .milliseconds(500))
        #expect(drawn.cues.map(\.text) == ["Track 4 two", "Sign"])
        // A seek back.
        drawn.update(at: .zero)
        #expect(drawn.cues.map(\.text) == ["Track 4 one"])
        #expect(drawn.update(at: .seconds(9)) == nil)

        try pick("+0.25 s", in: DrawnSubtitles.delayMenuID, of: playback)
        try pick("+0.25 s", in: DrawnSubtitles.delayMenuID, of: playback)
        #expect(drawn.delay == .milliseconds(500))
        let menu = playback.accessories.menus.first { $0.id == DrawnSubtitles.delayMenuID }
        #expect(menu?.title == "Subtitle delay: +0.5 s")
        // Half a second later than the file says.
        drawn.update(at: .milliseconds(2250))
        #expect(drawn.cues.map(\.text) == ["Track 4 one"])
        drawn.update(at: .milliseconds(2600))
        #expect(drawn.cues.isEmpty)

        try pick("-1 s", in: DrawnSubtitles.delayMenuID, of: playback)
        #expect(drawn.delay == .milliseconds(-500))
        try pick("reset", in: DrawnSubtitles.delayMenuID, of: playback)
        #expect(drawn.delay == .zero)
    }

    @Test func `the delay menu shows while subtitles are drawn, and each entry starts without a delay`() async throws {
        let drawn = drawn()
        let playback = player(drawn)
        await start(playback)
        #expect(await eventually { playback.accessories.menus.contains { $0.id == DrawnSubtitles.delayMenuID } })
        drawn.changeDelay(by: .seconds(1))

        try pick("subtitles.off", in: "subtitles", of: playback)
        #expect(await eventually { !playback.accessories.menus.contains { $0.id == DrawnSubtitles.delayMenuID } })
        try pick("subtitles.6", in: "subtitles", of: playback)
        #expect(await eventually { drawn.track?.index == 6 })
        let menu = playback.accessories.menus.first { $0.id == DrawnSubtitles.delayMenuID }
        #expect(menu?.title == "Subtitle delay: +1 s")

        let next = PlaybackStream.withSubtitleFiles("m2", TrackRequest(mediaSourceID: "m2", audioIndex: 1))
        await drawn.handle(.loaded(next, playback.queue.current), in: playback)
        #expect(drawn.delay == .zero)
        #expect(drawn.track == nil)
        #expect(!playback.accessories.menus.contains { $0.id == DrawnSubtitles.delayMenuID })
    }

    @Test func `a file that can't be fetched shows nothing, nor a file for a replaced pick`() async throws {
        let drawn = drawn(failing: [6], slow: [5], delay: .milliseconds(200))
        let playback = player(drawn)
        await start(playback)
        #expect(await cues(at: .seconds(1), in: drawn) == ["Track 4 one"])

        try pick("subtitles.6", in: "subtitles", of: playback)
        #expect(await eventually { fetches.all.count == 2 })
        try? await Task.sleep(for: .milliseconds(50))
        #expect(drawn.update(at: .seconds(1)) == nil)
        #expect(drawn.cues.isEmpty)
        #expect(drawn.track?.index == 6)

        try pick("subtitles.forced", in: "subtitles", of: playback)
        #expect(await eventually { fetches.all.count == 3 })
        try pick("subtitles.4", in: "subtitles", of: playback)
        #expect(await eventually { drawn.track?.index == 4 })
        try? await Task.sleep(for: .milliseconds(300))
        #expect(await cues(at: .seconds(1), in: drawn) == ["Track 4 one"])
        // The forced track's file came late, and wasn't kept.
        #expect(fetches.all.map(\.index) == [4, 6, 5])
    }

    @Test func `following the engine keeps what shows up to date`() async {
        let drawn = drawn()
        let playback = player(drawn)
        await start(playback)
        #expect(await cues(at: .seconds(1), in: drawn) == ["Track 4 one"])
        engine.currentTime = .seconds(3)

        let following = Task { await drawn.follow() }
        #expect(await eventually { drawn.cues.isEmpty })
        engine.currentTime = .milliseconds(6500)
        #expect(await eventually { drawn.cues.map(\.text) == ["Track 4 two", "Sign"] })
        engine.currentTime = .milliseconds(1500)
        #expect(await eventually { drawn.cues.map(\.text) == ["Track 4 one"] })
        following.cancel()
    }

    @Test func `only text subtitles of the stream playing are drawn`() async throws {
        let drawn = drawn()
        let playback = player(drawn)
        await start(playback)
        #expect(await eventually { drawn.track?.index == 4 })
        let tracks = [MediaTrack].multiTrack

        let other = PlaybackStream.withSubtitleFiles("m9", nil)
        drawn.show(tracks.first { $0.index == 6 }, in: other)
        #expect(drawn.track?.index == 4)
        let playing = try #require(playback.stream)
        drawn.show(tracks.first { $0.index == 8 }, in: playing)
        #expect(drawn.track == nil)
        #expect(fetches.all.count == 1)
    }

    @Test func `video in HDR or Dolby Vision takes the HDR style`() {
        func stream(_ range: VideoRangeType?) -> PlaybackStream {
            PlaybackStream(
                itemID: "m1",
                url: URL(filePath: "/m1"),
                method: .directPlay,
                video: range.map { MediaVersion.Video(range: $0) },
            )
        }

        #expect(stream(.hdr10).isHDR)
        #expect(stream(.dovi).isHDR)
        #expect(stream(.hlg).isHDR)
        #expect(!stream(.sdr).isHDR)
        #expect(!stream(.doviWithSDR).isHDR)
        #expect(!stream(.unknown).isHDR)
        #expect(!stream(nil).isHDR)
    }
}

/// Telling drawn subtitles from those the stream carries.
struct DrawnSubtitleSwitchingTests {
    private let stream = PlaybackStream.withSubtitleFiles("m1", TrackRequest(audioIndex: 1, subtitleIndex: 4))

    private func track(_ index: Int) throws -> MediaTrack {
        try #require(stream.tracks.first { $0.index == index })
    }

    @Test func `text subtitles sent as files are drawn, and the playlist then has none`() throws {
        #expect(try [4, 5, 6].allSatisfy { try TrackSwitching.isDrawn(track($0), in: stream) })
        #expect(try !TrackSwitching.isDrawn(track(8), in: stream))
        #expect(TrackSwitching.listed(.subtitle, in: stream).isEmpty)
        #expect(try TrackSwitching.subtitle(
            from: track(4),
            to: track(6),
            in: stream,
            options: [],
            burnsInStyled: true,
        ) == .drawn(track(6)))
        #expect(try TrackSwitching.subtitle(from: track(4), to: nil, in: stream, options: [], burnsInStyled: true)
            == .inPlace(nil))
    }

    @Test func `picture subtitles, and ASS on AVPlayer, are still burned in`() throws {
        #expect(try TrackSwitching.subtitle(from: track(4), to: track(7), in: stream, options: [], burnsInStyled: true)
            == .reload)
        #expect(try TrackSwitching.subtitle(from: track(4), to: track(8), in: stream, options: [], burnsInStyled: true)
            == .reload)
        // Where it isn't burned in, as with MPV, the server's plain text of it is drawn.
        #expect(try TrackSwitching.subtitle(from: nil, to: track(7), in: stream, options: [], burnsInStyled: false)
            == .drawn(track(7)))
    }

    @Test func `a live stream doesn't offer subtitles sent as files`() throws {
        #expect(try !TrackSwitching.switchesInPlace(to: track(4), in: stream, burnsInStyled: true))
    }
}

/// The subtitle files a test's fake server was asked for.
final class SubtitleFetchLog: Sendable {
    private let requests = Mutex<[SubtitleFileRequest]>([])

    var all: [SubtitleFileRequest] {
        requests.withLock(\.self)
    }

    func append(_ request: SubtitleFileRequest) {
        requests.withLock { $0.append(request) }
    }
}

extension SubtitleTimeline {
    /// A track's file: a line from 0 to 2 s, another from 5 to 8 s, and a sign from 6 to 7 s.
    static func numbered(_ index: Int) -> SubtitleTimeline {
        SubtitleTimeline([
            SubtitleCue(start: .zero, end: .seconds(2), lines: [SubtitleLine([SubtitleSpan("Track \(index) one")])]),
            SubtitleCue(
                start: .seconds(5),
                end: .seconds(8),
                lines: [SubtitleLine([SubtitleSpan("Track \(index) two")])],
            ),
            SubtitleCue(
                start: .seconds(6),
                end: .seconds(7),
                lines: [SubtitleLine([SubtitleSpan("Sign")])],
                placement: .top,
            ),
        ])
    }
}

extension PlaybackStream {
    /// What Jellyfin sends AVPlayer for `request`: HLS whose text subtitles come as files of their
    /// own, unless subtitles are burned in.
    static func withSubtitleFiles(_ itemID: String, _ request: TrackRequest?) -> PlaybackStream {
        let hls = PlaybackStream.hls(itemID, request, method: .directStream)
        let tracks = hls.tracks.map { track in
            var track = track
            if track.delivery == .hls {
                track.delivery = .external
            }
            return track
        }
        return PlaybackStream(
            itemID: hls.itemID,
            url: hls.url,
            method: hls.method,
            playSessionID: hls.playSessionID,
            mediaSourceID: hls.mediaSourceID,
            audioStreamIndex: hls.audioStreamIndex,
            subtitleStreamIndex: hls.subtitleStreamIndex,
            tracks: tracks,
        )
    }
}
