import AnemoneJellyfin
@testable import AnemonePlayback
import Foundation
import Testing

/// Up Next at the credits: when the outro starts, once for each, in place of segment skipping's
/// button, and what moving on from them reports.
@MainActor
struct UpNextCreditsTests: UpNextHarness {
    let engine = FakeEngine()
    let log = EventLog()

    @Test func `during the credits, Up Next shows while playing and Cancel keeps them playing`() async throws {
        let (playback, upNext) = try player(countdown: .seconds(100), timing: .duringCredits)
        await play(playback)

        upNext.creditsStarted(id: "c1")
        #expect(playback.accessories.card?.id == UpNext.upNextCard)
        try perform("upNext.cancel", on: playback)

        #expect(playback.accessories.card == nil)
        #expect(!playback.hasEnded)
        #expect(engine.isPlaying)
        // Once for the same credits, then again at the end, as in Wholphin.
        upNext.creditsStarted(id: "c1")
        #expect(playback.accessories.card == nil)
        engine.send(.ended)
        #expect(await eventually { playback.accessories.card?.id == UpNext.upNextCard })
        try perform("upNext.cancel", on: playback)
        #expect(playback.hasEnded)
    }

    @Test func `at the end of playback, the credits don't bring Up Next early`() async throws {
        let (playback, upNext) = try player(timing: .endOfPlayback)
        await play(playback)

        upNext.creditsStarted(id: "c1")

        #expect(playback.accessories.card == nil)
    }

    @Test func `an Up Next shown during the credits carries on past the end`() async throws {
        let (playback, upNext) = try player(countdown: .seconds(100), timing: .duringCredits)
        await play(playback)
        upNext.creditsStarted(id: "c1")

        engine.send(.ended)
        _ = await eventually { log.events.last == "stopped 100.0 seconds" }

        #expect(playback.accessories.card?.id == UpNext.upNextCard)
        #expect(!playback.hasEnded)
        // Cancel now closes the player, as it does at the end.
        try perform("upNext.cancel", on: playback)
        #expect(playback.hasEnded)
    }

    @Test func `during the credits, the outro segment brings Up Next`() async throws {
        let outro = MediaSegment(id: "o1", kind: .outro, start: .seconds(20), end: .seconds(100))
        let segments = SegmentSkipping(load: { _ in [outro] }, behavior: { _ in .ignore })
        let (playback, _) = try player(countdown: .seconds(100), timing: .duringCredits, others: [segments])
        await play(playback)
        try await Task.sleep(for: .milliseconds(50))
        #expect(playback.accessories.card == nil)

        engine.currentTime = .seconds(21)

        #expect(await eventually { playback.accessories.card?.id == UpNext.upNextCard })
        #expect(segments.current == outro)
    }

    @Test func `at the outro, Up Next comes up in place of the skip button`() async throws {
        let outro = MediaSegment(id: "o1", kind: .outro, start: .seconds(20), end: .seconds(90))
        let segments = SegmentSkipping(load: { _ in [outro] }, behavior: { _ in .ask })
        // Hears each event right after segment skipping, before Up Next.
        let probe = EventLog()
        var sawSkip = false
        probe.onEvent = { _, controller in
            sawSkip = sawSkip || controller.accessories.actions.contains { $0.id == SegmentSkipping.skipActionID }
        }
        let (playback, _) = try player(countdown: .seconds(100), timing: .duringCredits, others: [segments, probe])
        await play(playback)
        _ = await eventually { !segments.segments.isEmpty }

        engine.currentTime = .seconds(21)
        #expect(await eventually { playback.accessories.card?.id == UpNext.upNextCard })
        try await Task.sleep(for: .milliseconds(50))

        #expect(!sawSkip)
        #expect(segments.offered == nil)
        // Cancel keeps the credits playing, and the button can show then, as in Wholphin.
        try perform("upNext.cancel", on: playback)
        #expect(await eventually { segments.offered == outro })
    }

    @Test func `a cancelled Up Next doesn't come back at the same credits after a retry`() async throws {
        let outro = MediaSegment(id: "o1", kind: .outro, start: .seconds(20), end: .seconds(90))
        let segments = SegmentSkipping(load: { _ in [outro] }, behavior: { _ in .ignore })
        let (playback, _) = try player(countdown: .seconds(100), timing: .duringCredits, others: [segments])
        await play(playback)
        engine.currentTime = .seconds(21)
        _ = await eventually { playback.accessories.card?.id == UpNext.upNextCard }
        try perform("upNext.cancel", on: playback)

        // The direct play fails in the credits, and a transcode takes over from there.
        engine.send(.failed(PlayerError.streamFailed(underlying: nil)))
        await getUnderWay(loads: 2)
        try await Task.sleep(for: .milliseconds(50))

        #expect(segments.current == outro)
        #expect(playback.accessories.card == nil)
    }

    @Test func `an Up Next still up when the stream failed comes back after the retry`() async throws {
        let outro = MediaSegment(id: "o1", kind: .outro, start: .seconds(20), end: .seconds(90))
        let segments = SegmentSkipping(load: { _ in [outro] }, behavior: { _ in .ignore })
        let (playback, _) = try player(countdown: .seconds(100), timing: .duringCredits, others: [segments])
        await play(playback)
        engine.currentTime = .seconds(21)
        _ = await eventually { playback.accessories.card?.id == UpNext.upNextCard }

        engine.send(.failed(PlayerError.streamFailed(underlying: nil)))
        _ = await eventually { playback.accessories.card == nil }
        await getUnderWay(loads: 2)

        #expect(await eventually { playback.accessories.card?.id == UpNext.upNextCard })
    }

    @Test func `the next entry's credits bring Up Next again`() async throws {
        // Every entry has the same segment, as with `-fakeSegments`.
        let outro = MediaSegment(id: "o1", kind: .outro, start: .seconds(20), end: .seconds(90))
        let segments = SegmentSkipping(load: { _ in [outro] }, behavior: { _ in .ignore })
        let (playback, _) = try player(countdown: .seconds(100), timing: .duringCredits, others: [segments])
        await play(playback)
        engine.currentTime = .seconds(21)
        _ = await eventually { playback.accessories.card?.id == UpNext.upNextCard }

        try perform("upNext.play", on: playback)
        await getUnderWay(loads: 2)

        #expect(await eventually { playback.accessories.card?.id == UpNext.upNextCard })
        #expect(playback.queue.current.itemID == "e2")
    }

    @Test func `moving on from the credits ends the entry as played`() async throws {
        let (playback, upNext) = try player(countdown: .seconds(100), timing: .duringCredits)
        await play(playback)
        engine.currentTime = .seconds(70)
        upNext.creditsStarted(id: "c1")

        try perform("upNext.play", on: playback)

        #expect(await eventually { engine.loads.count == 2 })
        // At its end (the fake engine's 100 s), not at 70 s, so the server marks it played.
        #expect(log.events.suffix(2) == ["stopped 100.0 seconds", "loaded e2 directPlay"])
    }

    @Test func `autoplaying from the credits ends the entry as played`() async throws {
        let (playback, upNext) = try player(countdown: .seconds(1), timing: .duringCredits)
        await play(playback)
        engine.currentTime = .seconds(70)

        upNext.creditsStarted(id: "c1")

        #expect(await eventually { engine.loads.count == 2 })
        #expect(upNext.autoplaysWithoutInput == 1)
        #expect(log.events.suffix(2) == ["stopped 100.0 seconds", "loaded e2 directPlay"])
    }

    @Test func `at the end of playback, the outro segment doesn't bring Up Next`() async throws {
        let outro = MediaSegment(id: "o1", kind: .outro, start: .seconds(20), end: .seconds(100))
        let segments = SegmentSkipping(load: { _ in [outro] }, behavior: { _ in .ignore })
        let (playback, _) = try player(timing: .endOfPlayback, others: [segments])
        await play(playback)

        engine.currentTime = .seconds(21)
        _ = await eventually { segments.current == outro }
        try await Task.sleep(for: .milliseconds(50))

        #expect(playback.accessories.card == nil)
    }

    @Test func `the test credits start brings Up Next at that position`() async throws {
        let (playback, _) = try player(countdown: .seconds(100), testCreditsStart: .seconds(20))
        await play(playback)
        try await Task.sleep(for: .milliseconds(50))
        #expect(playback.accessories.card == nil)

        engine.currentTime = .seconds(21)

        #expect(await eventually { playback.accessories.card?.id == UpNext.upNextCard })
    }
}
