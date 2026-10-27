import AnemoneJellyfin
@testable import AnemonePlayback
import Foundation
import Testing

/// Up Next at the credits when playback goes back before them, when an entry is started again,
/// and when it moves on at once.
@MainActor
struct UpNextCreditsSeekTests: UpNextHarness {
    let engine = FakeEngine()
    let log = EventLog()
    private let outro = MediaSegment(id: "o1", kind: .outro, start: .seconds(20), end: .seconds(90))

    @Test func `seeking back out of the credits takes Up Next down until they play again`() async throws {
        let segments = SegmentSkipping(load: { [outro] _ in [outro] }, behavior: { _ in .ignore })
        let (playback, _) = try player(countdown: .seconds(100), timing: .duringCredits, others: [segments])
        await play(playback)
        engine.currentTime = .seconds(21)
        #expect(await eventually { playback.accessories.card?.id == UpNext.upNextCard })

        engine.currentTime = .seconds(10)

        #expect(await eventually { playback.accessories.card == nil })
        #expect(engine.loads.count == 1)
        // The user didn't cancel it, so the credits bring it again.
        engine.currentTime = .seconds(25)
        #expect(await eventually { playback.accessories.card?.id == UpNext.upNextCard })
    }

    @Test func `a countdown that ends just after seeking back out of the credits doesn't move on`() async throws {
        let segments = SegmentSkipping(load: { [outro] _ in [outro] }, behavior: { _ in .ignore })
        // No positions while it counts down, so only the countdown's end can see the seek.
        let (playback, upNext) = try player(
            countdown: .seconds(3),
            timing: .duringCredits,
            others: [segments],
            positionInterval: .seconds(60),
        )
        await playback.start()
        _ = await eventually { engine.loads.count == 1 && !segments.segments.isEmpty }
        engine.currentTime = .seconds(21)
        engine.send(.ready)
        #expect(await eventually { playback.accessories.card?.id == UpNext.upNextCard })

        engine.currentTime = .seconds(10)

        #expect(await eventually { playback.accessories.card == nil })
        try await Task.sleep(for: .milliseconds(50))
        #expect(engine.loads.count == 1)
        #expect(upNext.autoplaysWithoutInput == 0)
        // Not ended at its end, as if played.
        #expect(!log.events.contains { $0.hasPrefix("stopped") })
    }

    @Test func `an entry the server won't offer, then a return, leaves the credits to bring Up Next`() async throws {
        let segments = SegmentSkipping(load: { [outro] _ in [outro] }, behavior: { _ in .ignore })
        let (playback, _) = try player(
            countdown: .seconds(100),
            timing: .duringCredits,
            others: [segments],
            streams: FakeStreams(failingItems: ["e2"]),
        )
        await play(playback)
        engine.currentTime = .seconds(21)
        _ = await eventually { playback.accessories.card?.id == UpNext.upNextCard }
        try perform("upNext.cancel", on: playback)

        // The next entry fails before it loads, and the user goes back to this one.
        playback.play(entryAt: 1)
        #expect(await eventually { log.events.last == "failed" })
        playback.play(entryAt: 0)
        await getUnderWay(loads: 2)

        // Another start of the entry, not a retry of its stream: its credits bring Up Next again.
        #expect(await eventually { playback.accessories.card?.id == UpNext.upNextCard })
    }

    @Test func `after a reloaded stream's retry, starting the entry again brings Up Next again`() async throws {
        let segments = SegmentSkipping(load: { [outro] _ in [outro] }, behavior: { _ in .ignore })
        let (playback, _) = try player(countdown: .seconds(100), timing: .duringCredits, others: [segments])
        await play(playback)
        engine.currentTime = .seconds(21)
        _ = await eventually { playback.accessories.card?.id == UpNext.upNextCard }
        try perform("upNext.cancel", on: playback)

        // A reload (for a track), whose stream fails and is retried as a transcode: all `reloaded`.
        playback.reload()
        await getUnderWay(loads: 2)
        engine.send(.failed(PlayerError.streamFailed(underlying: nil)))
        await getUnderWay(loads: 3)
        #expect(log.events.count(where: { $0.hasPrefix("reloaded") }) == 2)
        #expect(playback.accessories.card == nil)

        playback.play(entryAt: 0)
        await getUnderWay(loads: 4)

        #expect(await eventually { playback.accessories.card?.id == UpNext.upNextCard })
    }

    @Test func `an entry the server won't offer, then a return, leaves this entry's segments to skip`() async throws {
        let intro = MediaSegment(id: "i1", kind: .intro, start: .seconds(5), end: .seconds(30))
        let segments = SegmentSkipping(load: { _ in [intro] }, behavior: { _ in .autoSkip })
        let (playback, _) = try player(others: [segments], streams: FakeStreams(failingItems: ["e2"]))
        await play(playback)
        _ = await eventually { !segments.segments.isEmpty }
        engine.currentTime = .seconds(6)
        #expect(await eventually { engine.currentTime == intro.end + .milliseconds(1) })

        playback.play(entryAt: 1)
        #expect(await eventually { log.events.last == "failed" })
        playback.play(entryAt: 0)
        await getUnderWay(loads: 2)
        _ = await eventually { !segments.segments.isEmpty }
        engine.currentTime = .seconds(6)

        // Skipped again, as in an entry started afresh.
        #expect(await eventually { engine.currentTime == intro.end + .milliseconds(1) })
    }

    @Test func `with no countdown, the credits move on without offering this entry's Skip Outro`() async throws {
        let segments = SegmentSkipping(load: { [outro] _ in [outro] }, behavior: { _ in .ask })
        // Hears each event right after segment skipping.
        let probe = EventLog()
        var sawSkip = false
        probe.onEvent = { _, controller in
            sawSkip = sawSkip || controller.accessories.actions.contains { $0.id == SegmentSkipping.skipActionID }
        }
        let (playback, _) = try player(countdown: .zero, timing: .duringCredits, others: [segments, probe])
        await play(playback)
        _ = await eventually { !segments.segments.isEmpty }

        engine.currentTime = .seconds(21)

        #expect(await eventually { engine.loads.count == 2 })
        try await Task.sleep(for: .milliseconds(50))
        #expect(!sawSkip)
        #expect(segments.offered == nil)
        // Moving on from the credits ends the entry as played.
        #expect(log.events.contains("stopped 100.0 seconds"))
    }

    @Test func `with no countdown, the old entry's segment and button go as the credits move on`() async throws {
        let recap = MediaSegment(id: "r1", kind: .recap, start: .seconds(10), end: .seconds(20))
        let segments = SegmentSkipping(load: { [outro] _ in [recap, outro] }, behavior: { _ in .ask })
        // Hears each event right after segment skipping: what's left the moment it moves on.
        let probe = EventLog()
        var leftOver: [String]?
        probe.onEvent = { _, controller in
            guard controller.queue.currentIndex == 1, leftOver == nil else { return }
            let actions = controller.accessories.actions.map(\.id)
            leftOver = [segments.offered?.id, segments.current?.id].compactMap(\.self) + actions
        }
        let (playback, _) = try player(countdown: .zero, timing: .duringCredits, others: [segments, probe])
        await play(playback)
        _ = await eventually { !segments.segments.isEmpty }
        engine.currentTime = .seconds(11)
        #expect(await eventually { segments.offered == recap })

        engine.currentTime = .seconds(21)

        #expect(await eventually { engine.loads.count == 2 })
        // No segment offered or playing, and no skip button. Before, the recap's button and the
        // outro lasted until the next entry's events: "r1", "o1", "segments.skip".
        #expect(leftOver == [])
    }

    @Test func `with no countdown, the credits move on without skipping them in the next entry`() async throws {
        let segments = SegmentSkipping(load: { [outro] _ in [outro] }, behavior: { _ in .autoSkip })
        let (playback, _) = try player(countdown: .zero, timing: .duringCredits, others: [segments])
        await play(playback)
        _ = await eventually { !segments.segments.isEmpty }

        engine.currentTime = .seconds(21)

        #expect(await eventually { engine.loads.count == 2 })
        try await Task.sleep(for: .milliseconds(50))
        // No seek to the old entry's credits' end while the next loads.
        #expect(engine.currentTime == .seconds(21))
    }
}
