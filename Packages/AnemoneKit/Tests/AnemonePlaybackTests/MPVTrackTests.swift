import AnemoneCore
import AnemoneJellyfin
@testable import AnemonePlayback
import Foundation
import JellyfinAPI
import Testing

/// The track menus while MPV plays: it shows ASS and picture subtitles itself, so they're
/// neither burned in nor asked for in another stream, and it lists the subtitle files beside the
/// video after the file's own, so those map to the tracks it added for them.
@MainActor
struct MPVTrackTests {
    private let client = FakeMPVClient()
    private let log = EventLog()
    private let requests = StreamRequestLog()
    private let defaults: UserDefaults

    init() throws {
        let suite = "MPVTrackTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
    }

    /// The fixture's multi-track file, with an Italian SRT beside it.
    private nonisolated static let tracks: [MediaTrack] = .multiTrack + [
        MediaTrack(
            index: 10,
            kind: .subtitle,
            language: "ita",
            displayTitle: "Italian - SUBRIP - External",
            codec: "subrip",
            isExternal: true,
        ),
    ]

    private func selection(_ profile: ProfileTrackSettings = .english) -> TrackSelection {
        TrackSelection(
            server: TrackSelection.Server(
                itemTracks: { ItemTracks(itemID: $0, sources: [.init(id: $0, tracks: Self.tracks)]) },
                profileSettings: { profile },
            ),
            store: TrackChoiceStore(userID: "u1", defaults: defaults),
            defaults: defaults,
        )
    }

    /// What Jellyfin sends MPV's profile for the file: the file itself, its subtitles in it, the
    /// one beside it as External.
    private nonisolated static func stream(_ request: StreamRequest) -> PlaybackStream {
        PlaybackStream(
            itemID: request.itemID,
            url: URL(filePath: "/\(request.itemID).mkv"),
            method: .directPlay,
            playSessionID: "ps",
            mediaSourceID: request.itemID,
            audioStreamIndex: request.audioStreamIndex,
            subtitleStreamIndex: request.subtitleStreamIndex,
            tracks: tracks.map { track in
                var track = track
                if track.kind == .subtitle {
                    track.delivery = track.isExternal ? .external : .embedded
                }
                return track
            },
        )
    }

    private func pick(_ optionID: String, in playback: PlaybackController) throws {
        let menu = playback.accessories.menus.first { $0.id == "subtitles" }
        try #require(menu?.options.first { $0.id == optionID }).select()
    }

    @Test func `only AVPlayer has ASS burned in`() async throws {
        let spanish = selection(ProfileTrackSettings(
            audioLanguage: "eng",
            subtitleLanguage: "spa",
            subtitleMode: .always,
        ))

        let mpv = await spanish.request(for: "m1", mediaSourceID: nil, profile: MPVProfile.deviceProfile())
        let avPlayer = await spanish.request(for: "m1", mediaSourceID: nil, profile: AVPlayerProfile.deviceProfile())

        #expect(mpv == TrackRequest(mediaSourceID: "m1", audioIndex: 1, subtitleIndex: 7))
        #expect(avPlayer == TrackRequest(mediaSourceID: "m1", audioIndex: 1, subtitleIndex: 7, burnsInSubtitles: true))
        #expect(try #require(mpv).profile(from: MPVProfile.deviceProfile()) == MPVProfile.deviceProfile())
    }

    /// MPV playing the file, once it has added the Italian file to its tracks.
    private func playing(features: [any PlaybackFeature] = []) async throws -> PlaybackController {
        let session = try StubServer.session(host: "mpv-tracks.test")
        let engine = MPVPlayerEngine.testing(client)
        let playback = PlaybackController(
            request: PlaybackRequest(.item("m1")),
            engine: engine,
            features: [selection(), MPVExternalSubtitles(session: session)] + features + [log],
        ) { [requests] request in
            requests.append(request)
            return Self.stream(request)
        }
        // libmpv lists the file's tracks: three audio, then six subtitles.
        client.list(
            (1 ... 3).map { FakeMPVClient.Track(type: "audio", id: $0) }
                + (1 ... 6).map { FakeMPVClient.Track(type: "sub", id: $0) },
        )

        await playback.start()
        engine.start(client.entries[0])
        engine.handle(.property("pause", .flag(false)))
        #expect(await eventually { log.events.contains { $0.hasPrefix("started") } })
        // The Italian file beside the video, added after the file's own.
        #expect(await eventually { client.tracks.count { $0.type == "sub" } == 7 })
        return playback
    }

    @Test func `on MPV, ASS, pictures and files beside the video switch in the player`() async throws {
        let playback = try await playing()

        try pick("subtitles.8", in: playback)
        #expect(await eventually { client.lastSet("sid") == "5" })
        try pick("subtitles.7", in: playback)
        #expect(await eventually { client.lastSet("sid") == "4" })
        try pick("subtitles.10", in: playback)
        #expect(await eventually { client.lastSet("sid") == "7" })

        // One stream, asked for with MPV's own profile: nothing burned in.
        #expect(client.entries.count == 1)
        #expect(requests.sent.count == 1)
        #expect(requests.sent.first?.profile == MPVProfile.deviceProfile())
        await playback.stop()
    }

    @Test func `a switch in the player has the debug panel read the engine's tracks again`() async throws {
        let details = PlaybackDetails { _, _ in SeekPreviews() }
        let playback = try await playing(features: [details])
        // The stream loaded, then the tracks chosen for it selected in the engine.
        #expect(await eventually { details.trackChanges == 2 })

        try pick("subtitles.8", in: playback)

        // Before, only a new stream did, so its check mark stayed on the track switched from.
        #expect(await eventually { details.trackChanges == 3 })
        #expect(client.lastSet("sid") == "5")
        #expect(client.entries.count == 1)
        await playback.stop()
    }
}
