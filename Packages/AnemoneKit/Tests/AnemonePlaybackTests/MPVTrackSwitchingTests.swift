import AnemoneCore
import AnemoneJellyfin
@testable import AnemonePlayback
import Foundation
import Testing

/// Which of MPV's subtitle tracks is the server's: MPV lists the file's own, then the files it
/// adds beside it, and says which are which.
struct MPVTrackSwitchingTests {
    /// MPV lists the subtitles in the file, then the files beside it that it adds, in the
    /// server's order, then any it's given later, such as a downloaded one.
    @Test func `on MPV, subtitles go by position, the files it adds after the file's own`() {
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
        // MPV says which are files: here, all but the first three.
        func options(_ count: Int) -> [PlayerTrack] {
            (1 ... count).map { PlayerTrack(
                id: $0,
                kind: .subtitle,
                title: "Track \($0)",
                language: nil,
                isSelected: false,
                isExternal: $0 > 3,
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

    /// The server sends a track in the file that MPV can't read (TTML) as a file instead, which
    /// MPV adds: it lists the track in the file and the file, where the server lists it once.
    @Test func `on MPV, a track in the file that's sent as a file moves no other track`() {
        let tracks = [
            MediaTrack(index: 4, kind: .subtitle, language: "eng", codec: "subrip", delivery: .embedded),
            MediaTrack(index: 6, kind: .subtitle, language: "jpn", codec: "ttml", delivery: .external),
            MediaTrack(index: 7, kind: .subtitle, language: "spa", codec: "ass", delivery: .embedded),
            MediaTrack(
                index: 10,
                kind: .subtitle,
                language: "ita",
                codec: "subrip",
                isExternal: true,
                delivery: .external,
            ),
        ]
        let stream = PlaybackStream(itemID: "m1", url: URL(filePath: "/m1.mp4"), method: .directPlay, tracks: tracks)
        func option(_ id: Int, _ language: String, _ codec: String, file: Bool) -> PlayerTrack {
            PlayerTrack(
                id: id,
                kind: .subtitle,
                title: "Track \(id)",
                language: language,
                isSelected: false,
                codec: codec,
                isExternal: file,
            )
        }
        // As libmpv lists them: the file's three, then the TTML as SRT and the Italian file.
        let options = [
            option(1, "en", "subrip", file: false),
            option(2, "ja", "ttml", file: false),
            option(3, "es", "ass", file: false),
            option(4, "ja", "subrip", file: true),
            option(5, "it", "subrip", file: true),
        ]
        func mapped(_ index: Int) -> Int? {
            tracks.first { $0.index == index }.flatMap {
                TrackSwitching.playerTrack(for: $0, in: stream, options: options, rendering: .mpv)?.id
            }
        }

        #expect(TrackSwitching.listed(.subtitle, in: stream, rendering: .mpv).map(\.index) == [4, 7, 6, 10])
        // Before, by position: 7 got the TTML in the file, 6 the Spanish, and 10 the TTML's file.
        #expect([4, 7, 6, 10].map(mapped) == [1, 3, 4, 5])
    }

    /// Jellyfin's playlist has subtitles only when the ones asked for come in it, as for AVPlayer.
    @Test func `on MPV in HLS, a file or burned-in subtitle asked for leaves the playlist without any`() {
        func stream(asking index: Int) -> PlaybackStream {
            PlaybackStream(
                itemID: "m1",
                url: URL(filePath: "/m1.m3u8"),
                method: .transcode,
                subtitleStreamIndex: index,
                tracks: [
                    MediaTrack(index: 4, kind: .subtitle, language: "eng", codec: "subrip", delivery: .hls),
                    MediaTrack(index: 5, kind: .subtitle, language: "eng", codec: "subrip", delivery: .hls),
                    MediaTrack(
                        index: 8,
                        kind: .subtitle,
                        language: "ger",
                        codec: "pgssub",
                        isText: false,
                        delivery: .burnedIn,
                    ),
                    MediaTrack(
                        index: 10,
                        kind: .subtitle,
                        language: "ita",
                        codec: "subrip",
                        isExternal: true,
                        delivery: .external,
                    ),
                ],
            )
        }
        let italian = MediaTrack(index: 10, kind: .subtitle, language: "ita", codec: "subrip", delivery: .external)
        // MPV lists only the file it added.
        let options = [PlayerTrack(id: 1, kind: .subtitle, title: "Italian", language: "it", isSelected: true)]

        #expect(TrackSwitching.listed(.subtitle, in: stream(asking: 4), rendering: .mpv).map(\.index) == [4, 5, 10])
        for asked in [8, 10] {
            let playing = stream(asking: asked)
            #expect(TrackSwitching.listed(.subtitle, in: playing, rendering: .mpv).map(\.index) == [10])
            // Before, the playlist's two went first, so the file was looked for third.
            #expect(TrackSwitching.playerTrack(for: italian, in: playing, options: options, rendering: .mpv)
                == options.first)
        }
    }
}
