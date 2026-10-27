import AnemoneCore
import AnemoneJellyfin
@testable import AnemonePlayback
import Foundation
import JellyfinAPI
import Testing

/// Choosing tracks before the stream is asked for, the Audio and Subtitles menus, switching,
/// and remembering choices for the item and the series.
@MainActor
struct TrackSelectionTests {
    private let engine = TrackEngine()
    private let log = EventLog()
    private let defaults: UserDefaults
    private let store: TrackChoiceStore
    private let requests = TrackRequestLog()

    init() throws {
        let suite = "TrackSelectionTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        store = TrackChoiceStore(userID: "u1", defaults: defaults)
    }

    /// A feature for items with the fixture's multi-track file, or episodes with English and
    /// Japanese audio and English and Spanish subtitles, and a profile that likes English.
    private func selection(profile: ProfileTrackSettings = .english) -> TrackSelection {
        TrackSelection(
            server: TrackSelection.Server(
                itemTracks: { id in
                    id.hasPrefix("e")
                        ? ItemTracks(
                            itemID: id,
                            seriesID: "show",
                            seasonID: "s2",
                            sources: [.init(id: id, tracks: .episode)],
                        )
                        : ItemTracks(itemID: id, sources: [.init(id: id, tracks: .multiTrack)])
                },
                profileSettings: { profile },
            ),
            store: store,
            defaults: defaults,
        )
    }

    /// A player that asks `selection` for tracks, as the real one does, and gets HLS back.
    private func player(
        _ selection: TrackSelection,
        playing itemID: String = "m1",
        method: PlaybackMethod = .directStream,
    ) -> PlaybackController {
        PlaybackController(
            request: PlaybackRequest(.item(itemID)),
            engine: engine,
            features: [selection, log],
            positionInterval: .milliseconds(10),
        ) { [requests] itemID, _, sourceID in
            let choice = await selection.request(for: itemID, mediaSourceID: sourceID)
            requests.append(choice)
            return PlaybackStream.hls(itemID, choice, method: method)
        }
    }

    private func start(_ playback: PlaybackController) async {
        await playback.start()
        engine.send(.ready)
        _ = await eventually { log.events.contains { $0.hasPrefix("started") } }
    }

    private func menu(_ id: String, in playback: PlaybackController) -> PlayerMenu? {
        playback.accessories.menus.first { $0.id == id }
    }

    private func pick(_ optionID: String, in menuID: String, of playback: PlaybackController) throws {
        try #require(menu(menuID, in: playback)?.options.first { $0.id == optionID }).select()
    }

    @Test func `tracks are chosen by the settings before the stream is asked for`() async throws {
        let playback = player(selection())

        await start(playback)

        // English AAC, and the default English subtitles, with the profile in Default mode.
        #expect(requests.all == [TrackRequest(mediaSourceID: "m1", audioIndex: 1, subtitleIndex: 4)])
        let audio = try #require(menu("audio", in: playback))
        #expect(audio.options.map(\.id) == ["audio.1", "audio.2", "audio.3"])
        #expect(audio.options.filter(\.isSelected).map(\.id) == ["audio.1"])
        let subtitles = try #require(menu("subtitles", in: playback))
        #expect(subtitles.options.map(\.id) == [
            "subtitles.off", "subtitles.forced", "subtitles.4", "subtitles.5", "subtitles.6", "subtitles.7",
            "subtitles.8", "subtitles.9",
        ])
        #expect(subtitles.options.filter(\.isSelected).map(\.id) == ["subtitles.4"])
        // The HLS playlist's subtitles are SRT, forced, SDH and ASS: the first is selected.
        #expect(await eventually { engine.selected[.subtitle] == 0 })
    }

    @Test func `subtitles are selected again once playback is under way`() async {
        let playback = player(selection())

        await start(playback)

        // AVPlayer showed none until then.
        #expect(await eventually { engine.subtitleSelections.suffix(2) == [nil, 0] })
    }

    @Test func `a styled ASS track is burned in`() async throws {
        let selection = selection(profile: ProfileTrackSettings(
            audioLanguage: "eng",
            subtitleLanguage: "spa",
            subtitleMode: .always,
        ))

        let request = await selection.request(for: "m1", mediaSourceID: nil)

        #expect(request == TrackRequest(mediaSourceID: "m1", audioIndex: 1, subtitleIndex: 7, burnsInSubtitles: true))
        let profile = try #require(request).profile(from: AVPlayerProfile.deviceProfile())
        #expect(profile.subtitleProfiles?.allSatisfy { $0.method == .encode } == true)
        #expect(profile.subtitleProfiles?.contains { $0.format == "ass" } == true)
    }

    @Test func `switching audio in HLS asks for another stream from the same position`() async throws {
        let playback = player(selection())
        await start(playback)
        engine.currentTime = .seconds(42)

        try pick("audio.2", in: "audio", of: playback)

        #expect(await eventually { log.events.count { $0.hasPrefix("loaded") } == 2 })
        #expect(requests.all.last == TrackRequest(mediaSourceID: "m1", audioIndex: 2, subtitleIndex: 4))
        #expect(engine.loads.last?.position == .seconds(42))
        #expect(log.events.after("stopped 42.0 seconds") == ["loaded m1 directStream"])
        #expect(menu("audio", in: playback)?.options.filter(\.isSelected).map(\.id) == ["audio.2"])
    }

    @Test func `switching audio in a file that plays directly happens in the player`() async throws {
        let playback = player(selection(), method: .directPlay)
        engine.options[.audio] = [
            PlayerTrack(id: 0, kind: .audio, title: "English", language: "en", isSelected: true),
            PlayerTrack(id: 1, kind: .audio, title: "French", language: "fr", isSelected: false),
            PlayerTrack(id: 2, kind: .audio, title: "Japanese", language: "ja", isSelected: false),
        ]
        await start(playback)

        try pick("audio.3", in: "audio", of: playback)

        #expect(await eventually { engine.selected[.audio] == 2 })
        #expect(engine.loads.count == 1)
    }

    @Test func `text subtitles switch in the player, burned-in ones take another stream`() async throws {
        let playback = player(selection())
        await start(playback)

        try pick("subtitles.6", in: "subtitles", of: playback)
        #expect(await eventually { engine.selected[.subtitle] == 2 })

        try pick("subtitles.off", in: "subtitles", of: playback)
        #expect(await eventually { engine.selected[.subtitle] == .some(nil) })
        #expect(engine.loads.count == 1)

        // PGS can only be burned in.
        try pick("subtitles.8", in: "subtitles", of: playback)
        #expect(await eventually { engine.loads.count == 2 })
        #expect(requests.all.last == TrackRequest(mediaSourceID: "m1", audioIndex: 1, subtitleIndex: 8))

        // Taking it away takes another stream too.
        try pick("subtitles.4", in: "subtitles", of: playback)
        #expect(await eventually { engine.loads.count == 3 })
        #expect(requests.all.last == TrackRequest(mediaSourceID: "m1", audioIndex: 1, subtitleIndex: 4))
    }

    @Test func `only forced finds the forced track in the audio's language`() async throws {
        let playback = player(selection(profile: ProfileTrackSettings(subtitleMode: SubtitleMode.none)))
        await start(playback)

        try pick("subtitles.forced", in: "subtitles", of: playback)

        // The forced English SRT, the second in the playlist.
        #expect(await eventually { engine.selected[.subtitle] == 1 })
        #expect(menu("subtitles", in: playback)?.options.filter(\.isSelected).map(\.id) == ["subtitles.forced"])
        #expect(store.itemChoice(for: "m1")?.subtitle == .onlyForced)
    }

    @Test func `a pick is remembered for the item`() async throws {
        let playback = player(selection())
        await start(playback)
        try pick("audio.3", in: "audio", of: playback)
        try pick("subtitles.off", in: "subtitles", of: playback)

        let request = await selection().request(for: "m1", mediaSourceID: nil)

        #expect(request == TrackRequest(mediaSourceID: "m1", audioIndex: 3, subtitleIndex: nil))
        // A movie's choice isn't kept for anything else.
        #expect(store.seriesChoices(.audio, seriesID: nil, seasonID: nil).isEmpty)
    }

    @Test func `a subtitle pick carries over to the next episode`() async throws {
        let playback = player(selection(), playing: "e2")
        await start(playback)
        #expect(requests.all == [TrackRequest(mediaSourceID: "e2", audioIndex: 1, subtitleIndex: nil)])

        try pick("subtitles.4", in: "subtitles", of: playback)

        #expect(store.seriesChoices(.subtitle, seriesID: "show", seasonID: "s2").map(\.parent) == [.season, .series])
        // Wholphin looks these up with the audio type, so its next episode would start
        // without subtitles again.
        let next = await selection().request(for: "e3", mediaSourceID: nil)
        #expect(next == TrackRequest(mediaSourceID: "e3", audioIndex: 1, subtitleIndex: 4))
    }

    @Test func `an audio pick carries over to the next episode without touching subtitles`() async throws {
        let playback = player(selection(), playing: "e2")
        await start(playback)

        try pick("audio.2", in: "audio", of: playback)

        #expect(store.seriesChoices(.subtitle, seriesID: "show", seasonID: "s2").isEmpty)
        let next = await selection().request(for: "e3", mediaSourceID: nil)
        #expect(next == TrackRequest(mediaSourceID: "e3", audioIndex: 2, subtitleIndex: nil))
    }

    @Test func `without the item's tracks the server's picks show in the menus`() async {
        let selection = TrackSelection(
            server: TrackSelection.Server(
                itemTracks: { _ in throw URLError(.notConnectedToInternet) },
                profileSettings: { .english },
            ),
            store: store,
            defaults: defaults,
        )
        let playback = PlaybackController(
            request: PlaybackRequest(.item("m1")),
            engine: engine,
            features: [selection, log],
        ) { [requests] itemID, _, _ in
            let choice = await selection.request(for: itemID, mediaSourceID: nil)
            requests.append(choice)
            return PlaybackStream.hls(itemID, TrackRequest(audioIndex: 2, subtitleIndex: 5), method: .directStream)
        }

        await start(playback)

        #expect(requests.all == [nil])
        #expect(menu("audio", in: playback)?.options.filter(\.isSelected).map(\.id) == ["audio.2"])
        #expect(menu("subtitles", in: playback)?.options.filter(\.isSelected).map(\.id) == ["subtitles.5"])
    }

    @Test func `a single audio track and no subtitles show no menus`() async {
        let tracks = [MediaTrack(index: 1, kind: .audio)]
        let selection = TrackSelection(
            server: TrackSelection.Server(
                itemTracks: { id in ItemTracks(itemID: id, sources: [.init(id: id, tracks: tracks)]) },
                profileSettings: { .english },
            ),
            store: store,
            defaults: defaults,
        )
        let playback = PlaybackController(
            request: PlaybackRequest(.item("m1")),
            engine: engine,
            features: [selection, log],
        ) { itemID, _, _ in
            let choice = await selection.request(for: itemID, mediaSourceID: nil)
            return PlaybackStream(
                itemID: itemID,
                url: URL(filePath: "/m1"),
                method: .directPlay,
                audioStreamIndex: choice?.audioIndex,
                tracks: tracks,
            )
        }

        await start(playback)

        #expect(playback.accessories.menus.isEmpty)
    }
}
