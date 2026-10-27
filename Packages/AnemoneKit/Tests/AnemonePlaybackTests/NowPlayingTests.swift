@testable import AnemonePlayback
import Foundation
import MediaPlayer
import Synchronization
import Testing

/// Now Playing, driven by a controller with a fake engine and a fake center that records what
/// the system would show and lets the tests send the remote's commands.
@MainActor
struct NowPlayingTests {
    private let engine = FakeEngine()
    private let center = FakeCenter()
    private let streams = FakeStreams()
    private let artworkRequests = ArtworkRequests()

    private static let poster = URL(filePath: "/poster.jpg")

    private func controller(
        _ entries: [PlaybackQueue.Entry] = [.item("m1")],
        startingAt index: Int = 0,
        usesSystemPlayer: Bool? = nil,
    ) throws -> (PlaybackController, NowPlaying) {
        let requests = artworkRequests
        let nowPlaying = NowPlaying(center: center) { url in
            requests.append(url)
            return Data("art \(url.lastPathComponent)".utf8)
        }
        nowPlaying.usesSystemPlayer = usesSystemPlayer
        let playback = try PlaybackController(
            request: PlaybackRequest(queue: #require(PlaybackQueue(entries: entries, startingAt: index))),
            engine: engine,
            features: [nowPlaying],
            positionInterval: .milliseconds(10),
            loadStream: streams.load,
        )
        return (playback, nowPlaying)
    }

    private static func entry(_ id: String, from position: Duration? = nil) -> PlaybackQueue.Entry {
        PlaybackQueue.Entry(
            itemID: id,
            startPosition: position,
            metadata: PlaybackMetadata(
                title: "Pioneer One",
                subtitle: "S1:E\(id.suffix(1)) · Earthfall",
                artworkURL: poster,
            ),
        )
    }

    @Test func `shows the entry with its artwork, and follows playback`() async throws {
        let (playback, nowPlaying) = try controller([Self.entry("e1", from: .seconds(60))])

        await playback.start()
        let shown = try #require(center.published.last ?? nil)
        #expect(shown.metadata.title == "Pioneer One")
        #expect(shown.position == .seconds(60))
        #expect(!shown.isPlaying)
        #expect(await eventually { nowPlaying.info?.artwork?.data == Data("art poster.jpg".utf8) })
        #expect(center.shown?.artwork?.data == Data("art poster.jpg".utf8))

        engine.currentTime = .seconds(61)
        engine.send(.ready)
        #expect(await eventually { nowPlaying.info?.isPlaying == true })
        #expect(nowPlaying.info?.duration == .seconds(100))
        engine.currentTime = .seconds(70)
        #expect(await eventually { nowPlaying.info?.position == .seconds(70) })

        engine.pause()
        #expect(await eventually { nowPlaying.info?.isPlaying == false })
        await playback.stop()
    }

    @Test func `the system's properties say what's playing`() {
        let info = NowPlayingInfo(
            metadata: PlaybackMetadata(title: "Pioneer One", subtitle: "S1:E1 · Earthfall"),
            position: .seconds(90),
            duration: .seconds(2700),
            isPlaying: false,
            rate: 1.5,
            queueIndex: 2,
            queueCount: 6,
        )

        let properties = info.properties
        #expect(properties[MPMediaItemPropertyTitle] as? String == "Pioneer One")
        #expect(properties[MPMediaItemPropertyArtist] as? String == "S1:E1 · Earthfall")
        #expect(properties[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double == 90)
        #expect(properties[MPMediaItemPropertyPlaybackDuration] as? Double == 2700)
        // Paused, the clock stands still.
        #expect(properties[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 0)
        #expect(properties[MPNowPlayingInfoPropertyDefaultPlaybackRate] as? Double == 1.5)
        #expect(properties[MPNowPlayingInfoPropertyPlaybackQueueIndex] as? Int == 2)
        #expect(properties[MPNowPlayingInfoPropertyPlaybackQueueCount] as? Int == 6)
        #expect(properties[MPNowPlayingInfoPropertyMediaType] as? UInt == MPNowPlayingInfoMediaType.video.rawValue)

        var playing = info
        playing.isPlaying = true
        playing.duration = nil
        #expect(playing.properties[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 1.5)
        #expect(playing.properties[MPMediaItemPropertyPlaybackDuration] == nil)
    }

    @Test func `play, pause and skips work the engine`() async throws {
        let (playback, nowPlaying) = try controller()
        await playback.start()
        engine.send(.ready)
        #expect(await eventually { nowPlaying.info?.isPlaying == true })

        #expect(center.send(.pause))
        #expect(!engine.isPlaying)
        #expect(await eventually { nowPlaying.info?.isPlaying == false })
        #expect(center.send(.togglePlayPause))
        #expect(engine.isPlaying)
        #expect(await eventually { nowPlaying.info?.isPlaying == true })
        #expect(center.send(.togglePlayPause))
        #expect(!engine.isPlaying)
        #expect(center.send(.play))
        #expect(engine.isPlaying)

        engine.currentTime = .seconds(50)
        #expect(center.send(.skip(.seconds(30))))
        #expect(await eventually { engine.currentTime == .seconds(80) })
        #expect(center.send(.skip(.seconds(30))))
        // Not past the end.
        #expect(await eventually { engine.currentTime == .seconds(100) })
        #expect(center.send(.skip(.seconds(-120))))
        #expect(await eventually { engine.currentTime == .zero })
        #expect(center.send(.seek(.seconds(42))))
        #expect(await eventually { engine.currentTime == .seconds(42) })
        await playback.stop()
    }

    @Test func `next and previous move through the queue`() async throws {
        let (playback, nowPlaying) = try controller([.item("e1"), .item("e2"), .item("e3")], startingAt: 1)
        await playback.start()
        #expect(center.commands == [
            .play, .pause, .togglePlayPause, .skipForward, .skipBackward, .changePosition, .nextTrack, .previousTrack,
        ])

        #expect(center.send(.next))
        #expect(await eventually { streams.received.map(\.itemID) == ["e2", "e3"] })
        #expect(await eventually { nowPlaying.info?.queueIndex == 2 })
        // The last entry has no next.
        #expect(!center.commands.contains(.nextTrack))
        #expect(center.commands.contains(.previousTrack))

        // Early on, Previous plays the entry before.
        engine.currentTime = .seconds(2)
        #expect(center.send(.previous))
        #expect(await eventually { streams.received.map(\.itemID) == ["e2", "e3", "e2"] })

        // Later, it goes back to the start.
        engine.send(.ready)
        engine.currentTime = .seconds(30)
        #expect(await eventually { nowPlaying.info?.queueIndex == 1 })
        #expect(center.send(.previous))
        #expect(await eventually { engine.currentTime == .zero })
        #expect(streams.received.count == 3)
        await playback.stop()
    }

    @Test func `next comes on once an episode's following episodes are found`() async {
        let nowPlaying = NowPlaying(center: center) { _ in nil }
        let playback = PlaybackController(
            request: PlaybackRequest(.item("e1")) { [.item("e2"), .item("e3")] },
            engine: engine,
            features: [nowPlaying],
            positionInterval: .milliseconds(10),
            loadStream: streams.load,
        )
        await playback.start()
        engine.send(.ready)

        #expect(await eventually { center.commands.contains(.nextTrack) })
        #expect(nowPlaying.info?.queueCount == 3)
        #expect(center.send(.next))
        #expect(await eventually { streams.received.map(\.itemID) == ["e1", "e2"] })
        await playback.stop()
    }

    @Test func `a single entry has no next or previous`() async throws {
        let (playback, _) = try controller()
        await playback.start()

        #expect(center.commands == [.play, .pause, .togglePlayPause, .skipForward, .skipBackward, .changePosition])
        #expect(center.send(.next) == false)
        await playback.stop()
    }

    @Test func `closing the player clears Now Playing and lets the remote go`() async throws {
        let (playback, nowPlaying) = try controller()
        await playback.start()
        #expect(center.isHandling)

        await playback.stop()

        #expect(!center.isHandling)
        #expect(center.published.last == .some(nil))
        #expect(nowPlaying.info == nil)
    }

    @Test func `with the system player, it leaves Now Playing and the remote to it`() async throws {
        let (playback, nowPlaying) = try controller([Self.entry("e1")], usesSystemPlayer: true)

        await playback.start()
        engine.send(.ready)
        #expect(await eventually { engine.isPlaying })
        #expect(await eventually { artworkRequests.urls == [Self.poster] })

        #expect(center.published.isEmpty)
        #expect(!center.isHandling)
        #expect(nowPlaying.info == nil)
        await playback.stop()
    }

    @Test func `a retry as a transcode keeps the artwork it has`() async throws {
        let (playback, nowPlaying) = try controller([Self.entry("e1")])
        await playback.start()
        #expect(await eventually { nowPlaying.info?.artwork != nil })

        engine.send(.failed(URLError(.cannotDecodeContentData)))

        #expect(await eventually { streams.received.map(\.allowsDirect) == [true, false] })
        #expect(await eventually { nowPlaying.info?.artwork != nil })
        #expect(artworkRequests.urls == [Self.poster])
        await playback.stop()
    }

    @Test func `a reload for another track keeps Now Playing and its artwork`() async throws {
        let (playback, nowPlaying) = try controller([Self.entry("e1")])
        await playback.start()
        engine.send(.ready)
        #expect(await eventually { nowPlaying.info?.artwork != nil })

        playback.reload()

        #expect(await eventually { streams.received.count == 2 })
        #expect(await eventually { nowPlaying.info?.artwork != nil && center.isHandling })
        #expect(artworkRequests.urls == [Self.poster])
        await playback.stop()
    }

    @Test func `the system's artwork is made once per entry, and position updates change only the timing`() throws {
        let system = FakeSystem()
        let center = SystemNowPlayingCenter(
            makeArtwork: { _ in
                system.artworks.append(NSObject())
                return system.artworks.last
            },
            write: { system.written.append($0) },
        )
        var info = NowPlayingInfo(
            metadata: PlaybackMetadata(title: "Pioneer One", subtitle: "S1:E1 · Earthfall"),
            artwork: NowPlayingArtwork(url: Self.poster, data: Data("art".utf8)),
            position: .seconds(1),
        )

        center.publish(info)
        info.isPlaying = true
        info.position = .seconds(2)
        info.duration = .seconds(2700)
        center.publish(info)

        #expect(system.artworks.count == 1)
        let shown = try #require(system.written.last ?? nil)
        #expect(shown[MPMediaItemPropertyArtwork] as? NSObject === system.artworks.first)
        #expect(shown[MPMediaItemPropertyTitle] as? String == "Pioneer One")
        #expect(shown[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double == 2)
        #expect(shown[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 1)
        #expect(shown[MPMediaItemPropertyPlaybackDuration] as? Double == 2700)

        // The next entry gets its own.
        info.metadata.subtitle = "S1:E2 · The Man From Mars"
        info.artwork = NowPlayingArtwork(url: URL(filePath: "/poster2.jpg"), data: Data("art 2".utf8))
        center.publish(info)
        #expect(system.artworks.count == 2)
        #expect((system.written.last ?? nil)?[MPMediaItemPropertyArtwork] as? NSObject === system.artworks.last)

        center.publish(nil)
        #expect(system.written.count == 4)
        #expect(system.written.last.flatMap(\.self) == nil)
        center.publish(info)
        #expect(system.artworks.count == 3)
    }
}
