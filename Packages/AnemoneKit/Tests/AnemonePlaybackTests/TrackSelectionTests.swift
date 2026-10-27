import AnemoneCore
import AnemoneJellyfin
@testable import AnemonePlayback
import Foundation
import JellyfinAPI
import Synchronization
import Testing

/// Choosing tracks before the stream is asked for, the Audio and Subtitles menus, switching,
/// and remembering choices for the item and the series.
@MainActor
struct TrackSelectionTests {
    private let engine = TrackEngine()
    private let log = EventLog()
    private let defaults: UserDefaults
    private let store: TrackChoiceStore
    private let requests = StreamRequestLog()

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
                    id.hasPrefix("m")
                        ? ItemTracks(itemID: id, sources: [.init(id: id, tracks: .multiTrack)])
                        : ItemTracks(
                            itemID: id,
                            seriesID: "show",
                            seasonID: "s2",
                            sources: [.init(id: id, tracks: .fixture(for: id))],
                        )
                },
                profileSettings: { profile },
            ),
            store: store,
            defaults: defaults,
        )
    }

    /// A player with `selection`, which puts its tracks in each request, and that gets HLS back.
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
        ) { [requests] request in
            requests.append(request)
            return PlaybackStream.hls(request.itemID, request.tracks, method: method)
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

        #expect(await eventually { log.events.contains { $0.hasPrefix("reloaded") } })
        #expect(requests.all.last == TrackRequest(mediaSourceID: "m1", audioIndex: 2, subtitleIndex: 4))
        #expect(engine.loads.last?.position == .seconds(42))
        #expect(log.events.after("stopped 42.0 seconds") == ["reloaded m1 directStream"])
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

    @Test func `only forced kept for the season stays only forced, so it follows the audio`() async throws {
        store.save(SeriesTrackChoice(parentID: "s2", parent: .season, kind: .subtitle, activation: .onlyForced))
        let playback = player(selection(profile: ProfileTrackSettings(subtitleMode: SubtitleMode.none)), playing: "f1")
        await start(playback)
        #expect(requests.all == [TrackRequest(mediaSourceID: "f1", audioIndex: 1, subtitleIndex: 3)])
        #expect(menu("subtitles", in: playback)?.options.filter(\.isSelected).map(\.id) == ["subtitles.forced"])

        try pick("audio.2", in: "audio", of: playback)

        // The Japanese forced subtitles, with Japanese audio.
        #expect(await eventually { requests.all.count == 2 })
        #expect(requests.all.last == TrackRequest(mediaSourceID: "f1", audioIndex: 2, subtitleIndex: 4))
        #expect(menu("subtitles", in: playback)?.options.filter(\.isSelected).map(\.id) == ["subtitles.forced"])
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
        ) { [requests] request in
            requests.append(request)
            return PlaybackStream.hls(
                request.itemID,
                TrackRequest(audioIndex: 2, subtitleIndex: 5),
                method: .directStream,
            )
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
        ) { request in
            PlaybackStream(
                itemID: request.itemID,
                url: URL(filePath: "/m1"),
                method: .directPlay,
                audioStreamIndex: request.audioStreamIndex,
                tracks: tracks,
            )
        }

        await start(playback)

        #expect(playback.accessories.menus.isEmpty)
    }
}

/// Fetching the tracks of one item while another's are on their way.
@MainActor
struct TrackSelectionFetchTests {
    private let defaults: UserDefaults
    private let store: TrackChoiceStore

    init() throws {
        let suite = "TrackSelectionFetchTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        store = TrackChoiceStore(userID: "u1", defaults: defaults)
    }

    @Test func `a fetch that a newer one replaced doesn't leave its item as the entry`() async throws {
        let (released, release) = AsyncStream.makeStream(of: Void.self)
        let isHeld = Mutex(false)
        let selection = TrackSelection(
            server: TrackSelection.Server(
                itemTracks: { id in
                    // The first episode's tracks come after the second's.
                    if id == "e1" {
                        isHeld.withLock { $0 = true }
                        for await _ in released {
                            break
                        }
                    }
                    return ItemTracks(
                        itemID: id,
                        seriesID: "show",
                        seasonID: "s2",
                        sources: [.init(id: id, tracks: .fixture(for: id))],
                    )
                },
                profileSettings: { .english },
            ),
            store: store,
            defaults: defaults,
        )
        let first = Task { await selection.request(for: "e1", mediaSourceID: nil) }
        #expect(await eventually { isHeld.withLock(\.self) })

        _ = await selection.request(for: "e2", mediaSourceID: nil)
        release.yield()
        _ = await first.value

        // The second episode, with its season and series, so what's picked in it is remembered
        // for them, rather than the server's picks for it.
        let entry = try #require(selection.entry)
        #expect(entry.itemID == "e2")
        #expect(entry.seasonID == "s2")
        #expect(entry.seriesID == "show")
    }
}
