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

    @Test func `only tracks the stream carries switch in place, as a live stream offers them`() throws {
        let direct = PlaybackStream.hls("m1", TrackRequest(audioIndex: 1, subtitleIndex: 4), method: .directPlay)
        let burned = PlaybackStream.hls("m1", TrackRequest(audioIndex: 1, subtitleIndex: 8), method: .transcode)
        func inPlace(_ index: Int, _ stream: PlaybackStream) throws -> Bool {
            try TrackSwitching.switchesInPlace(to: track(index), in: stream, burnsInStyled: true)
        }

        // Audio only in a file that plays directly; text subtitles, but not ASS or pictures.
        #expect(try [1, 2, 3].map { try inPlace($0, hls) } == [false, false, false])
        #expect(try [1, 2, 3].map { try inPlace($0, direct) } == [true, true, true])
        #expect(try [4, 5, 6, 7, 8].map { try inPlace($0, hls) } == [true, true, true, false, false])
        // Nothing while the server burns subtitles in.
        #expect(try !inPlace(4, burned))
    }

    @Test func `a request without burned-in subtitles keeps the profile`() {
        let profile = DeviceProfile(name: "Test", subtitleProfiles: [SubtitleProfile(format: "vtt", method: .hls)])

        #expect(TrackRequest(subtitleIndex: 4).profile(from: profile) == profile)
        #expect(TrackRequest(subtitleIndex: 7).subtitleStreamIndex == 7)
        #expect(TrackRequest().subtitleStreamIndex == -1)
    }
}
