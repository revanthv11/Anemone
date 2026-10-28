import AnemoneCore
import AnemoneJellyfin
@testable import AnemonePlayback
import Foundation
import Synchronization
import Testing

/// The Max bitrate menu: Wholphin's in-player bitrate change.
@MainActor
struct MaxBitrateMenuTests {
    /// Records the limit each request asked for.
    final class BitrateStreams: Sendable {
        private let limits = Mutex<[Int]>([])
        private let liveItems: Set<String>

        init(liveItems: Set<String> = []) {
            self.liveItems = liveItems
        }

        var requested: [Int] {
            limits.withLock(\.self)
        }

        var load: PlaybackController.StreamLoader {
            { [self] request in
                limits.withLock { $0.append(request.maxBitrate) }
                var stream = FakeStreams.stream(request.itemID, method: .directPlay)
                if liveItems.contains(request.itemID) {
                    stream = PlaybackStream(
                        itemID: stream.itemID,
                        url: stream.url,
                        method: stream.method,
                        playSessionID: stream.playSessionID,
                        mediaSourceID: stream.mediaSourceID,
                        liveStreamID: "live-\(request.itemID)",
                    )
                }
                return stream
            }
        }
    }

    /// Stands in for the Streaming setting, which another suite changes while tests run.
    static let setting = 100_000_000

    private func menu(of playback: PlaybackController) -> PlayerMenu? {
        playback.accessories.menus.first { $0.id == MaxBitrateMenu.menuID }
    }

    private func start(_ playback: PlaybackController, _ engine: FakeEngine, _ log: EventLog) async {
        await playback.start()
        engine.send(.ready)
        _ = await eventually { log.events.contains { $0.hasPrefix("started") } }
    }

    @Test func `the menu marks the setting's limit, and a pick reloads under it from the same position`() async {
        let engine = FakeEngine()
        let log = EventLog()
        let streams = BitrateStreams()
        let feature = MaxBitrateMenu { Self.setting }
        let playback = PlaybackController(
            request: PlaybackRequest(.item("m1")),
            engine: engine,
            features: [feature, log],
            loadStream: streams.load,
        )
        await start(playback, engine, log)
        #expect(streams.requested == [Self.setting])
        let bitrateMenu = menu(of: playback)
        #expect(bitrateMenu?.options.first { $0.isSelected }?.id == "maxBitrate.\(Self.setting)")
        #expect(bitrateMenu?.options.map(\.id).contains("maxBitrate.8000000") == true)
        engine.currentTime = .seconds(30)

        bitrateMenu?.options.first { $0.id == "maxBitrate.8000000" }?.select()

        #expect(await eventually { log.events.contains { $0.hasPrefix("reloaded") } })
        #expect(streams.requested == [Self.setting, 8_000_000])
        #expect(engine.loads.last?.position == .seconds(30))
        #expect(feature.pickedBitrate == 8_000_000)
        #expect(menu(of: playback)?.options.first { $0.isSelected }?.id == "maxBitrate.8000000")
    }

    @Test func `picking the limit already marked asks for nothing`() async {
        let engine = FakeEngine()
        let log = EventLog()
        let streams = BitrateStreams()
        let playback = PlaybackController(
            request: PlaybackRequest(.item("m1")),
            engine: engine,
            features: [MaxBitrateMenu { Self.setting }, log],
            loadStream: streams.load,
        )
        await start(playback, engine, log)

        menu(of: playback)?.options.first { $0.isSelected }?.select()
        try? await Task.sleep(for: .milliseconds(100))

        #expect(streams.requested.count == 1)
        #expect(!log.events.contains { $0.hasPrefix("reloaded") })
    }

    @Test func `the next entry keeps the pick, and another player starts from the setting`() async throws {
        let engine = FakeEngine()
        let log = EventLog()
        let streams = BitrateStreams()
        let queue = try #require(PlaybackQueue(entries: [.item("m1"), .item("m2")]))
        let playback = PlaybackController(
            request: PlaybackRequest(queue: queue),
            engine: engine,
            features: [MaxBitrateMenu { Self.setting }, log],
            loadStream: streams.load,
        )
        await start(playback, engine, log)
        menu(of: playback)?.options.first { $0.id == "maxBitrate.20000000" }?.select()
        _ = await eventually { log.events.contains { $0.hasPrefix("reloaded") } }

        playback.playNext()

        #expect(await eventually { log.events.contains("loaded m2 directPlay") })
        #expect(streams.requested == [Self.setting, 20_000_000, 20_000_000])

        let second = PlaybackController(
            request: PlaybackRequest(.item("m3")),
            engine: FakeEngine(),
            features: [MaxBitrateMenu { Self.setting }],
            loadStream: streams.load,
        )
        await second.start()
        #expect(streams.requested.last == Self.setting)
    }

    @Test func `a live stream has no bitrate menu`() async {
        let engine = FakeEngine()
        let log = EventLog()
        let playback = PlaybackController(
            request: PlaybackRequest(.item("ch1")),
            engine: engine,
            features: [MaxBitrateMenu { Self.setting }, log],
            loadStream: BitrateStreams(liveItems: ["ch1"]).load,
        )
        await start(playback, engine, log)

        #expect(menu(of: playback) == nil)
    }

    @Test func `bitrates read as Wholphin shows them`() {
        #expect(750_000.bitrateText == "750 kbps")
        #expect(8_000_000.bitrateText == "8 Mbps")
        #expect(8_500_000.bitrateText == "8.5 Mbps")
    }
}
