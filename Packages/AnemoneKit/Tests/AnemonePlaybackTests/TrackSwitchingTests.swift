import AnemoneCore
import AnemoneJellyfin
@testable import AnemonePlayback
import Foundation
import JellyfinAPI
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

    @Test func `an HLS stream carries one audio track, so audio takes another stream`() throws {
        let options = [PlayerTrack(id: 0, kind: .audio, title: "English", language: "en", isSelected: true)]

        #expect(try TrackSwitching.audio(track(2), in: hls, options: options) == .reload)
        #expect(try TrackSwitching.playerTrack(for: track(1), in: hls, options: options) == options.first)
    }

    @Test func `an HLS stream lists every text subtitle, in order`() throws {
        #expect(TrackSwitching.listed(.subtitle, in: hls).map(\.index) == [4, 5, 6, 7])
        #expect(try TrackSwitching.subtitle(
            from: track(4),
            to: track(5),
            in: hls,
            options: playlistSubtitles,
        ) == .inPlace(playlistSubtitles[1]))
        #expect(try TrackSwitching.subtitle(
            from: track(4),
            to: nil,
            in: hls,
            options: playlistSubtitles,
        )
            == .inPlace(nil))
    }

    @Test func `picture subtitles and, on AVPlayer, ASS are burned in, while MPV shows ASS itself`() throws {
        #expect(try TrackSwitching.subtitle(
            from: nil,
            to: track(8),
            in: hls,
            options: playlistSubtitles,
        )
            == .reload)
        #expect(try TrackSwitching.subtitle(
            from: nil,
            to: track(7),
            in: hls,
            options: playlistSubtitles,
        )
            == .reload)
        #expect(try TrackSwitching.subtitle(
            from: nil,
            to: track(7),
            in: hls,
            options: playlistSubtitles,
            rendering: .mpv,
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
            rendering: .mpv,
        ) == .reload)
    }

    @Test func `a stream with burned-in subtitles lists none`() throws {
        let burned = PlaybackStream.hls("m1", TrackRequest(audioIndex: 1, subtitleIndex: 8), method: .transcode)

        #expect(TrackSwitching.listed(.subtitle, in: burned).isEmpty)
        #expect(try TrackSwitching
            .subtitle(from: track(8), to: nil, in: burned, options: []) == .reload)
    }

    @Test func `without matching counts, a track is found by name`() throws {
        let options = [
            PlayerTrack(id: 0, kind: .subtitle, title: "English - SUBRIP", language: "en", isSelected: false),
            PlayerTrack(id: 1, kind: .subtitle, title: "English SDH - SUBRIP", language: "en", isSelected: false),
        ]

        #expect(try TrackSwitching.playerTrack(for: track(6), in: hls, options: options) == options[1])
        #expect(try TrackSwitching.playerTrack(for: track(7), in: hls, options: options) == nil)
    }

    @Test func `only tracks the stream carries switch in place, as a live stream offers them`() throws {
        let direct = PlaybackStream.hls("m1", TrackRequest(audioIndex: 1, subtitleIndex: 4), method: .directPlay)
        let burned = PlaybackStream.hls("m1", TrackRequest(audioIndex: 1, subtitleIndex: 8), method: .transcode)
        func inPlace(_ index: Int, _ stream: PlaybackStream) throws -> Bool {
            try TrackSwitching.switchesInPlace(to: track(index), in: stream)
        }

        // Audio only in a file that plays directly; text subtitles, but not ASS or pictures.
        #expect(try [1, 2, 3].map { try inPlace($0, hls) } == [false, false, false])
        #expect(try [1, 2, 3].map { try inPlace($0, direct) } == [true, true, true])
        #expect(try [4, 5, 6, 7, 8].map { try inPlace($0, hls) } == [true, true, true, false, false])
        // Nothing while the server burns subtitles in.
        #expect(try !inPlace(4, burned))
    }

    /// MPV lists the subtitles in the file, then the files beside it that it adds, in the
    /// server's order, then any it's given later, such as a downloaded one.
    @Test func `MPV's subtitles go by position, the files it adds after the file's own`() {
        let tracks = [
            MediaTrack(index: 4, kind: .subtitle, language: "eng", codec: "subrip", delivery: .embedded),
            MediaTrack(index: 7, kind: .subtitle, language: "spa", codec: "ass", delivery: .embedded),
            MediaTrack(index: 8, kind: .subtitle, language: "ger", codec: "pgssub", isText: false, delivery: .embedded),
            MediaTrack(
                index: 10,
                kind: .subtitle,
                language: "eng",
                codec: "subrip",
                isExternal: true,
                delivery: .external,
            ),
        ]
        let stream = PlaybackStream(itemID: "m1", url: URL(filePath: "/m1.mkv"), method: .directPlay, tracks: tracks)
        func options(_ count: Int) -> [PlayerTrack] {
            (1 ... count).map { PlayerTrack(
                id: $0,
                kind: .subtitle,
                title: "Track \($0)",
                language: nil,
                isSelected: false,
            ) }
        }
        let withDownload = options(5)
        let fileOnly = options(3)

        #expect(TrackSwitching.listed(.subtitle, in: stream, rendering: .mpv).map(\.index) == [4, 7, 8, 10])
        #expect(TrackSwitching.playerTrack(for: tracks[3], in: stream, options: withDownload, rendering: .mpv)
            == withDownload[3])
        // Before the file has opened, MPV lists only the file's own.
        #expect(TrackSwitching.playerTrack(for: tracks[2], in: stream, options: fileOnly, rendering: .mpv)
            == fileOnly[2])
        #expect(TrackSwitching.playerTrack(for: tracks[3], in: stream, options: fileOnly, rendering: .mpv) == nil)
        // It shows ASS and pictures itself, where AVPlayer has them burned in.
        #expect(TrackSwitching.subtitle(
            from: tracks[0],
            to: tracks[2],
            in: stream,
            options: withDownload,
            rendering: .mpv,
        )
            == .inPlace(withDownload[2]))
        #expect(TrackSwitching.subtitle(
            from: tracks[0],
            to: tracks[1],
            in: stream,
            options: withDownload,
            rendering: .mpv,
        )
            == .inPlace(withDownload[1]))
        #expect(TrackSwitching.subtitle(from: tracks[0], to: tracks[2], in: stream, options: withDownload) == .reload)
    }

    @Test func `MPV still takes another stream for pictures a transcode burns in`() throws {
        let transcode = PlaybackStream.hls("m1", TrackRequest(audioIndex: 1, subtitleIndex: 4), method: .transcode)

        #expect(try TrackSwitching.subtitle(
            from: track(4),
            to: track(8),
            in: transcode,
            options: playlistSubtitles,
            rendering: .mpv,
        ) == .reload)
    }

    @Test func `a request without burned-in subtitles keeps the profile`() {
        let profile = DeviceProfile(name: "Test", subtitleProfiles: [SubtitleProfile(format: "vtt", method: .hls)])

        #expect(TrackRequest(subtitleIndex: 4).profile(from: profile) == profile)
        #expect(TrackRequest(subtitleIndex: 7).subtitleStreamIndex == 7)
        #expect(TrackRequest().subtitleStreamIndex == -1)
    }
}
