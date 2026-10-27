import AnemoneCore
import AnemoneJellyfin
@testable import AnemonePlayback
import Foundation
import Testing

/// Drawn subtitles as one stream replaces another.
extension DrawnSubtitlesTests {
    @Test func `a late word for a replaced stream leaves what waits for the next one`() async throws {
        let drawn = drawn()
        let playback = player(drawn)
        await start(playback)
        #expect(await eventually { drawn.track?.index == 4 })
        let first = try #require(playback.stream)
        try pick("audio.2", in: "audio", of: playback)
        #expect(await eventually { log.events.contains { $0.hasPrefix("reloaded") } })
        let second = try #require(playback.stream)
        let next = PlaybackStream.withSubtitleFiles("m1", TrackRequest(mediaSourceID: "m1", audioIndex: 3))
        try #require(Set([first, second, next]).count == 3)
        let tracks = [MediaTrack].multiTrack

        // Track selection says what to draw in the stream after this one, before the drawn
        // subtitles hear of it; then word comes, late, for the stream the second replaced.
        drawn.show(tracks.first { $0.index == 6 }, in: next)
        drawn.show(tracks.first { $0.index == 5 }, in: first)
        await drawn.handle(.reloaded(next), in: playback)

        // Before, the late word took the place of the next stream's.
        #expect(drawn.track?.index == 6)
    }
}
