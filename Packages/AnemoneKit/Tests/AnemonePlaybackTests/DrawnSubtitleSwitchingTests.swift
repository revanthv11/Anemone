import AnemoneCore
import AnemoneJellyfin
@testable import AnemonePlayback
import Foundation
import Testing

/// Telling drawn subtitles from those the stream carries.
struct DrawnSubtitleSwitchingTests {
    private let stream = PlaybackStream.withSubtitleFiles("m1", TrackRequest(audioIndex: 1, subtitleIndex: 4))

    private func track(_ index: Int) throws -> MediaTrack {
        try #require(stream.tracks.first { $0.index == index })
    }

    @Test func `text subtitles sent as files are drawn, and the playlist then has none`() throws {
        #expect(try [4, 5, 6].allSatisfy { try TrackSwitching.isSentAsFile(track($0), in: stream) })
        #expect(try !TrackSwitching.isSentAsFile(track(8), in: stream))
        #expect(TrackSwitching.listed(.subtitle, in: stream).isEmpty)
        #expect(try TrackSwitching.subtitle(
            from: track(4),
            to: track(6),
            in: stream,
            options: [],
        ) == .drawn(track(6)))
        #expect(try TrackSwitching.subtitle(from: track(4), to: nil, in: stream, options: [])
            == .inPlace(nil))
    }

    @Test func `picture subtitles, and ASS on AVPlayer, are still burned in`() throws {
        #expect(try TrackSwitching.subtitle(from: track(4), to: track(7), in: stream, options: [])
            == .reload)
        #expect(try TrackSwitching.subtitle(from: track(4), to: track(8), in: stream, options: [])
            == .reload)
    }

    @Test func `a live stream doesn't offer subtitles sent as files`() throws {
        #expect(try !TrackSwitching.switchesInPlace(to: track(4), in: stream))
    }

    @Test func `MPV's tracks include the files, so it switches among them and nothing is drawn`() throws {
        // What MPV lists once it has added the files beside the stream, in the server's order.
        let options = (1 ... 4).map {
            PlayerTrack(id: $0, kind: .subtitle, title: "Subtitle \($0)", language: "en", isSelected: $0 == 1)
        }

        #expect(TrackSwitching.listed(.subtitle, in: stream, rendering: .mpv).map(\.index) == [4, 5, 6, 7])
        #expect(try TrackSwitching.subtitle(
            from: track(4),
            to: track(6),
            in: stream,
            options: options,
            rendering: .mpv,
        ) == .inPlace(options[2]))
        #expect(try TrackSwitching.subtitle(
            from: nil,
            to: track(7),
            in: stream,
            options: options,
            rendering: .mpv,
        ) == .inPlace(options[3]))
        #expect(try TrackSwitching.switchesInPlace(to: track(4), in: stream, rendering: .mpv))
    }

    @Test @MainActor func `only AVPlayer has the files drawn`() {
        #expect(TrackSelection.rendering(in: TrackEngine()) == .avPlayer)
        #expect(TrackSelection.rendering(in: MPVPlayerEngine.testing(nil)) == .mpv)
    }
}

/// While MPV plays, the text subtitles the server sends as files of their own are MPV's: it adds
/// them to its own tracks (`MPVExternalSubtitles`), so drawing them as well would show every line
/// twice.
@MainActor
struct DrawnSubtitlesMPVTests {
    private let client = FakeMPVClient()
    private let log = EventLog()
    private let fetches = SubtitleFetchLog()
    private let defaults: UserDefaults

    init() throws {
        let suite = "DrawnSubtitlesMPVTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
    }

    /// MPV playing the fixture's multi-track file, chosen for a profile that likes English, from
    /// HLS whose text subtitles come as files of their own.
    private func player(_ drawn: DrawnSubtitles) throws -> PlaybackController {
        let selection = TrackSelection(
            server: TrackSelection.Server(
                itemTracks: { ItemTracks(itemID: $0, sources: [.init(id: $0, tracks: .multiTrack)]) },
                profileSettings: { .english },
            ),
            store: TrackChoiceStore(userID: "u1", defaults: defaults),
            defaults: defaults,
        )
        let session = try StubServer.session(host: "drawn-subtitles-mpv.test")
        return PlaybackController(
            request: PlaybackRequest(.item("m1")),
            engine: MPVPlayerEngine.testing(client),
            features: [drawn, selection, MPVExternalSubtitles(session: session), log],
        ) { request in
            // MPV's own profile has the server burn in picture subtitles only.
            .withSubtitleFiles(request.itemID, TrackRequest(
                mediaSourceID: request.mediaSourceID,
                audioIndex: request.audioStreamIndex,
                subtitleIndex: request.tracks?.subtitleIndex,
            ))
        }
    }

    private func pick(_ optionID: String, in playback: PlaybackController) throws {
        let menu = playback.accessories.menus.first { $0.id == "subtitles" }
        try #require(menu?.options.first { $0.id == optionID }).select()
    }

    @Test func `while MPV plays, it shows the subtitle files itself and nothing is drawn`() async throws {
        let drawn = DrawnSubtitles(server: DrawnSubtitles.Server(timeline: { [fetches] request in
            fetches.append(request)
            return .numbered(request.index)
        }))
        let playback = try player(drawn)
        let mpv = try #require(playback.engine.mpv)

        await playback.start()
        // Track selection has done its part before libmpv opens the file and adds the files.
        try await Task.sleep(for: .milliseconds(50))
        mpv.start(client.entries[0])
        mpv.handle(.property("pause", .flag(false)))
        #expect(await eventually { log.events.contains { $0.hasPrefix("started") } })
        try await Task.sleep(for: .milliseconds(50))

        // MPV shows the English SRT the server picked, once: there's nothing to draw.
        let added = client.commands.filter { $0.first == "sub-add" }
        #expect(added.map { $0[2] } == ["select", "auto", "auto", "auto"])
        #expect(added.first?[1].contains("/Subtitles/4/Stream.subrip") == true)
        #expect(client.lastSet("sid") != "no")
        #expect(drawn.track == nil)
        #expect(drawn.update(at: .seconds(1)) == nil)
        #expect(drawn.cues.isEmpty)
        #expect(!playback.accessories.menus.contains { $0.id == DrawnSubtitles.delayMenuID })

        // Switching is MPV's too, among the files it was given, without another stream.
        try pick("subtitles.6", in: playback)
        #expect(await eventually { client.lastSet("sid") == "3" })
        try pick("subtitles.off", in: playback)
        #expect(await eventually { client.lastSet("sid") == "no" })
        #expect(client.entries.count == 1)
        #expect(drawn.track == nil)
        #expect(fetches.all.isEmpty)
        await playback.stop()
    }
}
