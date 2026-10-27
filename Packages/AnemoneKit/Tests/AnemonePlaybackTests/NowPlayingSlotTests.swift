@testable import AnemonePlayback
import Foundation
import MediaPlayer
import Testing

/// Now Playing shared by several players: the system has one, which the player that published
/// last owns. And what it shows for music, and how it compares artwork.
@MainActor
struct NowPlayingSlotTests {
    private let engine = FakeEngine()
    private let center = FakeCenter()
    private let streams = FakeStreams()

    private static let poster = URL(filePath: "/poster.jpg")

    @Test func `a player that closes after the next one has loaded leaves the next one's Now Playing alone`() async {
        let slot = NowPlaying.Slot(center: center)
        // Its stop report outlasts the next player's loading, so its Now Playing hears `stopped` late.
        let slow = SlowStop()
        let closing = PlaybackController(
            request: PlaybackRequest(.item("m1")),
            engine: FakeEngine(),
            features: [slow, NowPlaying(slot: slot) { _ in nil }],
            loadStream: streams.load,
        )
        let next = PlaybackController(
            request: PlaybackRequest(.item("m2")),
            engine: engine,
            features: [NowPlaying(slot: slot) { _ in nil }],
            loadStream: streams.load,
        )
        await closing.start()

        let stopping = Task { await closing.stop() }
        await next.start()
        #expect(center.shown?.metadata.title == "Title m2")
        slow.gate.open()
        await stopping.value

        #expect(center.shown?.metadata.title == "Title m2")
        #expect(!center.published.contains { $0 == nil })
        #expect(center.isHandling)
        await next.stop()
        #expect(center.published.last == .some(nil))
        #expect(!center.isHandling)
    }

    @Test func `the system player takes Now Playing from a player still closing`() async {
        let slot = NowPlaying.Slot(center: center)
        let slow = SlowStop()
        let closing = PlaybackController(
            request: PlaybackRequest(.item("m1")),
            engine: FakeEngine(),
            features: [slow, NowPlaying(slot: slot) { _ in nil }],
            loadStream: streams.load,
        )
        let system = NowPlaying(slot: slot) { _ in nil }
        system.usesSystemPlayer = true
        let next = PlaybackController(
            request: PlaybackRequest(.item("m2")),
            engine: engine,
            features: [system],
            loadStream: streams.load,
        )
        await closing.start()
        let stopping = Task { await closing.stop() }

        await next.start()
        // What the closing player showed goes, so the system player's is all there is.
        #expect(center.published.last == .some(nil))
        #expect(!center.isHandling)
        let cleared = center.published.count
        slow.gate.open()
        await stopping.value
        #expect(center.published.count == cleared)
        await next.stop()
    }

    @Test func `artwork counts as the same by where it came from, so its image isn't compared`() {
        let info = NowPlayingInfo(
            metadata: PlaybackMetadata(title: "Pioneer One", artworkURL: Self.poster),
            artwork: NowPlayingArtwork(url: Self.poster, data: Data("art".utf8)),
        )
        var reloaded = info
        reloaded.artwork = NowPlayingArtwork(url: Self.poster, data: Data("other bytes".utf8))
        var other = info
        other.artwork = NowPlayingArtwork(url: URL(filePath: "/poster2.jpg"), data: Data("art".utf8))

        #expect(reloaded == info)
        #expect(reloaded.showsSameEntry(as: info))
        #expect(other != info)
        #expect(!other.showsSameEntry(as: info))
    }

    @Test func `a song shows as music, with its album`() {
        let info = NowPlayingInfo(
            metadata: PlaybackMetadata(title: "Thunderdays", subtitle: "Binaerpilot"),
            isMusic: true,
            album: "Promo",
        )

        let properties = info.properties
        #expect(properties[MPNowPlayingInfoPropertyMediaType] as? UInt == MPNowPlayingInfoMediaType.audio.rawValue)
        #expect(properties[MPMediaItemPropertyArtist] as? String == "Binaerpilot")
        #expect(properties[MPMediaItemPropertyAlbumTitle] as? String == "Promo")
    }
}
