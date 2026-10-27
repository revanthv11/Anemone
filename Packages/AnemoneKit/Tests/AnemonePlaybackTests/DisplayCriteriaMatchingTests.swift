import AnemoneJellyfin
@testable import AnemonePlayback
import Foundation
import Testing

/// The feature asking the display for a mode while a fake engine plays. The reset's wait ends
/// when a test says so (`ManualSleeps`), not by the clock, so a busy machine can't make a reset
/// fire early or late.
@MainActor
struct DisplayCriteriaMatchingTests {
    private let fakeDisplay = FakeDisplay()
    private let sleeps = ManualSleeps()
    private let display: DisplayCriteriaMatching.Display

    private static let sdrEpisode = MediaVersion.Video(codec: "h264", frameRate: 25, range: .sdr)

    init() {
        let fakeDisplay = fakeDisplay
        display = DisplayCriteriaMatching.Display(apply: { fakeDisplay.apply($0) }, sleep: sleeps.sleep)
    }

    /// A player whose server describes every entry's video as `video`, and holds back its answer
    /// for an item in `slowAnswers` until the test opens the gate.
    private func controller(
        _ entries: [PlaybackQueue.Entry] = [.item("m1")],
        usesSystemPlayer: Bool? = nil,
        video: MediaVersion.Video? = DisplayCriteriaTests.film,
        slowAnswers: [String: LoadGate] = [:],
        log: EventLog = EventLog(),
    ) throws -> PlaybackController {
        let matching = DisplayCriteriaMatching(
            display: display,
            decoders: VideoDecoders(hevc: true, av1: false, dolbyVision: true),
        )
        matching.usesSystemPlayer = usesSystemPlayer
        // The log hears each event after the matching has.
        return try PlaybackController(
            request: PlaybackRequest(queue: #require(PlaybackQueue(entries: entries))),
            engine: FakeEngine(),
            features: [matching, log],
        ) { request in
            await slowAnswers[request.itemID]?.wait()
            return PlaybackStream(
                itemID: request.itemID,
                url: URL(filePath: "/\(request.itemID)"),
                method: .directPlay,
                mediaSourceID: "src-\(request.itemID)",
                video: video,
            )
        }
    }

    private var requests: [DisplayCriteria?] {
        fakeDisplay.requests
    }

    /// Ends the pending reset's wait, as if its time had passed, and waits for the reset. A wait
    /// a cancelled reset left can still be ending, so it ends whichever waits are there.
    private func elapseReset() async -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while display.isResetPending {
            guard ContinuousClock.now < deadline else { return false }
            sleeps.elapse()
            try? await Task.sleep(for: .milliseconds(1))
        }
        return true
    }

    @Test func `asks for the playing version's mode, then the usual one after closing`() async throws {
        let playback = try controller()

        await playback.start()

        #expect(requests.count == 1)
        #expect(requests.first??.frameRate == 23.976)
        #expect(requests.first??.dynamicRange == .hdr10)
        #expect(display.criteria != nil)
        #expect(!display.isResetPending)

        await playback.stop()

        #expect(display.isResetPending)
        #expect(await eventually { sleeps.pending == [.seconds(2)] })
        #expect(requests.count == 1)
        #expect(await elapseReset())
        #expect(requests.last == .some(nil))
        #expect(display.criteria == nil)
    }

    @Test func `the next entry in a queue doesn't switch the display back in between`() async throws {
        let slowAnswer = LoadGate()
        let log = EventLog()
        let playback = try controller([.item("e1"), .item("e2")], slowAnswers: ["e2": slowAnswer], log: log)
        await playback.start()
        #expect(requests.count == 1)

        playback.playNext()

        // The first entry's session has ended, and the next one's PlaybackInfo is still out.
        #expect(await eventually { slowAnswer.isReached })
        #expect(log.events.contains { $0.hasPrefix("stopped") })
        #expect(!display.isResetPending)
        #expect(sleeps.started == 0)

        slowAnswer.open()
        #expect(await eventually { log.events.last == "loaded e2 directPlay" })
        // The same mode, so nothing more to ask.
        #expect(requests.count == 1)
        #expect(display.criteria?.frameRate == 23.976)

        await playback.stop()
        #expect(await elapseReset())
        #expect(requests.last == .some(nil))
    }

    @Test func `an entry that ended keeps its mode while the player stays open`() async throws {
        let log = EventLog()
        let playback = try controller(log: log)
        await playback.start()
        // As Up Next does while it counts down over the last frame.
        playback.closesAtEnd = false

        try #require(playback.engine as? FakeEngine).send(.ended)

        #expect(await eventually { log.events.last?.hasPrefix("stopped") == true })
        #expect(!display.isResetPending)
        #expect(display.criteria != nil)

        await playback.stop()
        #expect(display.isResetPending)
        #expect(await elapseReset())
        #expect(requests.last == .some(nil))
    }

    @Test func `a mode the display couldn't take is asked for again by the next entry`() async throws {
        // No window yet, or Match Content off.
        fakeDisplay.takesRequests = false
        let log = EventLog()
        let playback = try controller([.item("e1"), .item("e2")], log: log)
        await playback.start()
        #expect(requests.count == 1)
        #expect(display.criteria == nil)

        fakeDisplay.takesRequests = true
        playback.playNext()

        #expect(await eventually { log.events.last == "loaded e2 directPlay" })
        #expect(requests.count == 2)
        #expect(display.criteria?.frameRate == 23.976)
        await playback.stop()
        #expect(await elapseReset())
    }

    @Test func `a player opened straight after another keeps its mode`() async throws {
        let first = try controller()
        await first.start()
        await first.stop()
        #expect(display.isResetPending)

        let second = try controller(video: Self.sdrEpisode)
        await second.start()

        // The first player's reset was called off.
        #expect(!display.isResetPending)
        #expect(requests.map { $0?.dynamicRange } == [.hdr10, .sdr])
        #expect(display.criteria?.frameRate == 25)

        await second.stop()
        #expect(await elapseReset())
        #expect(requests.map { $0?.dynamicRange } == [.hdr10, .sdr, nil])
    }

    @Test func `a player that closes after the next one opened leaves the display to it`() async throws {
        let first = try controller()
        await first.start()
        let second = try controller(video: Self.sdrEpisode)
        await second.start()

        await first.stop()

        #expect(!display.isResetPending)
        #expect(requests.map { $0?.dynamicRange } == [.hdr10, .sdr])
        await second.stop()
        #expect(await elapseReset())
        #expect(requests.last == .some(nil))
    }

    @Test func `the system player matches the display itself`() async throws {
        let playback = try controller(usesSystemPlayer: true)

        await playback.start()
        await playback.stop()

        #expect(requests.isEmpty)
        #expect(display.criteria == nil)
        #expect(!display.isResetPending)
    }

    @Test func `the system player takes the display back from a player that just closed`() async throws {
        let overlay = try controller()
        await overlay.start()
        await overlay.stop()

        let system = try controller(usesSystemPlayer: true)
        await system.start()

        // At once, rather than in the middle of the system player's own matching.
        #expect(requests.count == 2)
        #expect(requests.last == .some(nil))
        #expect(!display.isResetPending)
        await system.stop()
        #expect(!display.isResetPending)
        #expect(requests.count == 2)
    }

    @Test func `without the video's details, the display is left alone`() async throws {
        let playback = try controller(video: nil)

        await playback.start()
        await playback.stop()

        #expect(requests.isEmpty)
        #expect(!display.isResetPending)
    }
}

/// What the display was asked for.
@MainActor
final class FakeDisplay {
    var requests: [DisplayCriteria?] = []
    /// Whether the display takes what it's asked for; not without a window, or with Match
    /// Content off.
    var takesRequests = true

    func apply(_ criteria: DisplayCriteria?) -> Bool {
        requests.append(criteria)
        return takesRequests
    }
}
