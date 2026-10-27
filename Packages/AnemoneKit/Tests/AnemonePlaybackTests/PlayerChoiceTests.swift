import AnemoneJellyfin
@testable import AnemonePlayback
import AVFoundation
import Foundation
import JellyfinAPI
import QuartzCore
import Testing

/// Wholphin's player choice, and the engine that follows it per entry.
@MainActor
struct PlayerChoiceTests {
    @Test func `each backend picks as Wholphin's does`() {
        let sdr = ItemVideo(isHDR: false, is4K: false)
        let hdr = ItemVideo(isHDR: true, is4K: true)
        let sdr4K = ItemVideo(isHDR: false, is4K: true)

        #expect(PlayerBackend.avPlayer.engine(for: sdr, hardwareDecoding: true) == .avPlayer)
        #expect(PlayerBackend.mpv.engine(for: hdr, hardwareDecoding: true) == .mpv)
        #expect(PlayerBackend.preferMPV.engine(for: sdr, hardwareDecoding: true) == .mpv)
        #expect(PlayerBackend.preferMPV.engine(for: hdr, hardwareDecoding: true) == .avPlayer)
        #expect(PlayerBackend.preferMPV.engine(for: sdr4K, hardwareDecoding: true) == .mpv)
        #expect(PlayerBackend.preferMPV.engine(for: sdr4K, hardwareDecoding: false) == .avPlayer)
        // Unknown video, such as when the item couldn't be fetched, goes to MPV.
        #expect(PlayerBackend.preferMPV.engine(for: nil, hardwareDecoding: false) == .mpv)
    }

    @Test func `with Prefer MPV each entry plays in the engine its video needs, keeping one of each`() async {
        var kinds: [String: EngineKind] = ["sdr": .mpv, "hdr": .avPlayer, "sdr2": .mpv]
        var made = 0
        let client = FakeMPVClient()
        let engine = SwitchingEngine(
            choose: { kinds.removeValue(forKey: $0.itemID) ?? .mpv },
            makeMPV: {
                made += 1
                return MPVPlayerEngine.testing(client)
            },
        )
        guard case let .layer(container) = engine.videoOutput else {
            Issue.record("Prefer MPV always draws into its own layer")
            return
        }

        await engine.prepare(for: .item("sdr"))
        #expect(engine.kind == .mpv)
        #expect(engine.mpv != nil)
        #expect(engine.deviceProfile.name == "Anemone MPV")
        #expect(container.sublayers?.count == 1)
        engine.rate = 1.5

        await engine.prepare(for: .item("hdr"))
        #expect(engine.kind == .avPlayer)
        #expect(engine.mpv == nil)
        #expect(engine.deviceProfile.name == "Anemone AVPlayer")
        #expect(container.sublayers?.first is AVPlayerLayer)
        #expect(engine.rate == 1.5)
        // MPV stopped what it was playing.
        #expect(client.commands.last == ["stop"])

        await engine.prepare(for: .item("sdr2"))
        #expect(engine.kind == .mpv)
        #expect(made == 1)
        #expect(client.lastSet("speed") == "1.5")
        #expect(container.sublayers?.count == 1)
    }

    /// The server is asked for the entry's video first; the player can close meanwhile.
    @Test func `with Prefer MPV a choice that comes back after the player stopped starts no engine`() async {
        var made = 0
        var answer: CheckedContinuation<EngineKind, Never>?
        let engine = SwitchingEngine(
            choose: { _ in await withCheckedContinuation { answer = $0 } },
            makeMPV: {
                made += 1
                return MPVPlayerEngine.testing(FakeMPVClient())
            },
        )
        guard case let .layer(container) = engine.videoOutput else {
            Issue.record("Prefer MPV always draws into its own layer")
            return
        }

        let preparing = Task { await engine.prepare(for: .item("sdr")) }
        #expect(await eventually { answer != nil })
        engine.stop()
        answer?.resume(returning: .mpv)
        await preparing.value

        #expect(made == 0)
        #expect(container.sublayers?.isEmpty ?? true)
        #expect(engine.mpv == nil)
    }

    @Test func `with Prefer MPV an entry's choice that a newer entry's overtook is dropped`() async {
        var answers: [String: CheckedContinuation<EngineKind, Never>] = [:]
        let engine = SwitchingEngine(
            choose: { entry in await withCheckedContinuation { answers[entry.itemID] = $0 } },
            makeMPV: { MPVPlayerEngine.testing(FakeMPVClient()) },
        )

        let first = Task { await engine.prepare(for: .item("hdr")) }
        #expect(await eventually { answers["hdr"] != nil })
        let second = Task { await engine.prepare(for: .item("sdr")) }
        #expect(await eventually { answers["sdr"] != nil })
        answers["sdr"]?.resume(returning: .mpv)
        await second.value
        answers["hdr"]?.resume(returning: .avPlayer)
        await first.value

        #expect(engine.kind == .mpv)
        #expect(engine.mpv != nil)
    }

    @Test func `with Prefer MPV only preparing an entry starts an engine`() async {
        var made = 0
        let engine = SwitchingEngine(
            choose: { _ in .mpv },
            makeMPV: {
                made += 1
                return MPVPlayerEngine.testing(FakeMPVClient())
            },
        )

        engine.rate = 1.5
        engine.pause()
        engine.stop()

        #expect(engine.currentTime == .zero)
        #expect(engine.duration == nil)
        #expect(await engine.seek(to: .seconds(5)) == false)
        #expect(await engine.tracks(.audio).isEmpty)
        #expect(made == 0)
        await engine.prepare(for: .item("sdr"))
        #expect(made == 1)
        #expect(engine.mpv?.rate == 1.5)
    }

    @Test func `the controller has a per-entry engine prepare for each new entry, but not for a retry`() async throws {
        let engine = PreparingEngine()
        let streams = FakeStreams()
        let queue = try #require(PlaybackQueue(entries: [.item("a"), .item("b")]))
        let controller = PlaybackController(
            request: PlaybackRequest(queue: queue),
            engine: engine,
            features: [],
            loadStream: streams.load,
        )

        await controller.start()
        #expect(await eventually { engine.loads.count == 1 })
        engine.send(.failed(PlayerError.streamFailed(underlying: nil)))
        #expect(await eventually { engine.loads.count == 2 })
        controller.playNext()
        #expect(await eventually { engine.loads.count == 3 })

        #expect(engine.prepared == ["a", "b"])
        await controller.stop()
    }
}

/// A `FakeEngine` that records the entries it prepared for.
@MainActor
final class PreparingEngine: PerEntryEngine {
    private let fake = FakeEngine()
    private(set) var prepared: [String] = []

    func prepare(for entry: PlaybackQueue.Entry) async {
        prepared.append(entry.itemID)
    }

    var loads: [FakeEngine.Load] {
        fake.loads
    }

    func send(_ event: PlayerEvent) {
        fake.send(event)
    }

    var deviceProfile: DeviceProfile {
        fake.deviceProfile
    }

    var videoOutput: PlayerVideoOutput {
        fake.videoOutput
    }

    func load(_ url: URL, from position: Duration?, metadata: PlaybackMetadata) -> AsyncStream<PlayerEvent> {
        fake.load(url, from: position, metadata: metadata)
    }

    func play() {
        fake.play()
    }

    func pause() {
        fake.pause()
    }

    func stop() {
        fake.stop()
    }

    func seek(to position: Duration) async -> Bool {
        await fake.seek(to: position)
    }

    var currentTime: Duration {
        fake.currentTime
    }

    var duration: Duration? {
        fake.duration
    }

    var rate: Float {
        get { fake.rate }
        set { fake.rate = newValue }
    }

    func tracks(_ kind: PlayerTrack.Kind) async -> [PlayerTrack] {
        await fake.tracks(kind)
    }

    func select(_ track: PlayerTrack?, _ kind: PlayerTrack.Kind) async {
        await fake.select(track, kind)
    }
}
