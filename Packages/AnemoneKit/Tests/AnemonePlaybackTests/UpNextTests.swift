import AnemoneJellyfin
@testable import AnemonePlayback
import Foundation
import Synchronization
import Testing

/// Up Next, autoplay and pass-out protection, driven through a controller and a fake engine.
/// A second of countdown takes 10 ms here.
@MainActor
struct UpNextTests {
    private let engine = FakeEngine()
    private let log = EventLog()

    private func player(
        _ ids: [String] = ["e1", "e2", "e3"],
        skipped: Int = 0,
        countdown: Duration = .seconds(3),
        autoplays: Bool = true,
        timing: UpNextTiming = .endOfPlayback,
        passOutCount: Int = 0,
        testCreditsStart: Duration? = nil,
        others: [any PlaybackFeature] = [],
    ) throws -> (PlaybackController, UpNext) {
        var queue = try #require(PlaybackQueue(entries: ids.map { .item($0) }))
        queue.skippedCount = skipped
        let upNext = UpNext(
            settings: UpNext.Settings(
                autoplays: autoplays,
                countdown: countdown,
                timing: timing,
                passOutCount: passOutCount,
                stillWatchingTimeout: .seconds(5),
                testCreditsStart: testCreditsStart,
            ),
            second: .milliseconds(10),
        )
        let playback = PlaybackController(
            request: PlaybackRequest(queue: queue),
            engine: engine,
            features: others + [log, upNext],
            positionInterval: .milliseconds(10),
            loadStream: FakeStreams().load,
        )
        return (playback, upNext)
    }

    /// Starts playback and gets the first entry under way.
    private func play(_ playback: PlaybackController) async {
        await playback.start()
        await getUnderWay(loads: 1)
    }

    /// Gets the latest entry loaded under way.
    private func getUnderWay(loads: Int) async {
        _ = await eventually { engine.loads.count == loads }
        engine.send(.ready)
        _ = await eventually { log.events.count(where: { $0.hasPrefix("started") }) == loads }
    }

    private func perform(_ actionID: String, on playback: PlaybackController) throws {
        let card = try #require(playback.accessories.card)
        try #require(card.actions.first { $0.id == actionID }).perform()
    }

    @Test func `at the end, Up Next counts down and plays the next entry`() async throws {
        let (playback, upNext) = try player()
        await play(playback)

        engine.send(.ended)

        #expect(await eventually { playback.accessories.card?.id == UpNext.upNextCard })
        #expect(playback.accessories.card?.message?.hasPrefix("Title e2\nPlays in") == true)
        #expect(!playback.hasEnded)
        #expect(await eventually { engine.loads.count == 2 })
        #expect(playback.queue.current.itemID == "e2")
        #expect(playback.accessories.card == nil)
        #expect(upNext.autoplaysWithoutInput == 1)
        // The first entry's session ended at its end, before the next loaded.
        #expect(log.events.suffix(3) == ["ended", "stopped 100.0 seconds", "loaded e2 directPlay"])
    }

    @Test func `pressing Play Now plays the next entry at once`() async throws {
        let (playback, upNext) = try player(countdown: .seconds(100))
        await play(playback)
        engine.send(.ended)
        _ = await eventually { playback.accessories.card != nil }

        try perform("upNext.play", on: playback)

        #expect(await eventually { engine.loads.count == 2 })
        #expect(playback.queue.current.itemID == "e2")
        #expect(upNext.autoplaysWithoutInput == 0)
    }

    @Test func `cancelling at the end closes the player`() async throws {
        let (playback, _) = try player(countdown: .seconds(100))
        await play(playback)
        engine.send(.ended)
        _ = await eventually { playback.accessories.card != nil }

        try perform("upNext.cancel", on: playback)

        #expect(playback.hasEnded)
        #expect(playback.accessories.card == nil)
        try await Task.sleep(for: .milliseconds(50))
        #expect(engine.loads.count == 1)
    }

    @Test func `without autoplay, Up Next waits to be picked`() async throws {
        let (playback, _) = try player(countdown: .seconds(1), autoplays: false)
        await play(playback)

        engine.send(.ended)

        #expect(await eventually { playback.accessories.card?.id == UpNext.upNextCard })
        #expect(playback.accessories.card?.message == "Title e2")
        try await Task.sleep(for: .milliseconds(100))
        #expect(engine.loads.count == 1)
        #expect(!playback.hasEnded)
    }

    @Test func `with no countdown, the next entry plays at once`() async throws {
        let (playback, upNext) = try player(countdown: .zero)
        await play(playback)
        engine.currentTime = .seconds(100)

        engine.send(.ended)

        #expect(await eventually { engine.loads.count == 2 })
        #expect(playback.queue.current.itemID == "e2")
        #expect(upNext.autoplaysWithoutInput == 1)
        #expect(log.events.suffix(2) == ["stopped 100.0 seconds", "loaded e2 directPlay"])
    }

    @Test func `the last entry closes the player as before`() async throws {
        let (playback, _) = try player(["e1"])
        await play(playback)

        engine.send(.ended)

        #expect(await eventually { playback.hasEnded })
        #expect(playback.accessories.card == nil)
    }

    @Test func `during the credits, Up Next shows while playing and Cancel keeps them playing`() async throws {
        let (playback, upNext) = try player(countdown: .seconds(100), timing: .duringCredits)
        await play(playback)

        upNext.creditsStarted()
        #expect(playback.accessories.card?.id == UpNext.upNextCard)
        try perform("upNext.cancel", on: playback)

        #expect(playback.accessories.card == nil)
        #expect(!playback.hasEnded)
        #expect(engine.isPlaying)
        // Once each entry, then again at the end, as in Wholphin.
        upNext.creditsStarted()
        #expect(playback.accessories.card == nil)
        engine.send(.ended)
        #expect(await eventually { playback.accessories.card?.id == UpNext.upNextCard })
        try perform("upNext.cancel", on: playback)
        #expect(playback.hasEnded)
    }

    @Test func `at the end of playback, the credits don't bring Up Next early`() async throws {
        let (playback, upNext) = try player(timing: .endOfPlayback)
        await play(playback)

        upNext.creditsStarted()

        #expect(playback.accessories.card == nil)
    }

    @Test func `an Up Next shown during the credits carries on past the end`() async throws {
        let (playback, upNext) = try player(countdown: .seconds(100), timing: .duringCredits)
        await play(playback)
        upNext.creditsStarted()

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

    @Test func `after enough autoplays with no press, Still watching stops playback`() async throws {
        let (playback, upNext) = try player(countdown: .seconds(1), passOutCount: 1)
        await play(playback)
        engine.send(.ended)
        await getUnderWay(loads: 2)
        #expect(upNext.autoplaysWithoutInput == 1)

        engine.send(.ended)

        #expect(await eventually { playback.accessories.card?.id == UpNext.stillWatchingCard })
        #expect(playback.accessories.card?.message?.hasPrefix("Next: Title e3\nStopping in") == true)
        #expect(await eventually { playback.hasEnded })
        #expect(engine.loads.count == 2)
        #expect(playback.accessories.card == nil)
    }

    @Test func `keeping watching plays the next entry and counts again from 0`() async throws {
        let (playback, upNext) = try player(countdown: .seconds(1), passOutCount: 1)
        await play(playback)
        engine.send(.ended)
        await getUnderWay(loads: 2)
        engine.send(.ended)
        _ = await eventually { playback.accessories.card?.id == UpNext.stillWatchingCard }

        try perform("stillWatching.continue", on: playback)

        #expect(await eventually { engine.loads.count == 3 })
        #expect(playback.queue.current.itemID == "e3")
        #expect(upNext.autoplaysWithoutInput == 0)
    }

    @Test func `stopping closes the player`() async throws {
        let (playback, _) = try player(countdown: .seconds(1), passOutCount: 1)
        await play(playback)
        engine.send(.ended)
        await getUnderWay(loads: 2)
        engine.send(.ended)
        _ = await eventually { playback.accessories.card?.id == UpNext.stillWatchingCard }

        try perform("stillWatching.stop", on: playback)

        #expect(playback.hasEnded)
    }

    @Test func `a press on the remote or a resume counts as someone awake`() async throws {
        let (playback, upNext) = try player(countdown: .seconds(1), passOutCount: 1)
        await play(playback)
        engine.send(.ended)
        await getUnderWay(loads: 2)

        upNext.noteRemoteInput()
        #expect(upNext.autoplaysWithoutInput == 0)
        engine.send(.ended)
        #expect(await eventually { playback.accessories.card?.id == UpNext.upNextCard })
        #expect(await eventually { engine.loads.count == 3 })
        await getUnderWay(loads: 3)
        #expect(upNext.autoplaysWithoutInput == 1)

        engine.pause()
        engine.play()
        #expect(await eventually { upNext.autoplaysWithoutInput == 0 })
    }

    @Test func `closing the player takes Up Next down`() async throws {
        let (playback, _) = try player(countdown: .seconds(100), timing: .duringCredits)
        await play(playback)
        playback.feature(UpNext.self)?.creditsStarted()
        #expect(playback.accessories.card != nil)

        await playback.stop()

        #expect(playback.accessories.card == nil)
    }

    @Test func `a queue built without some items says so once`() async throws {
        let (playback, _) = try player(skipped: 2)
        await play(playback)

        #expect(playback.accessories.card?.id == UpNext.skippedCard)
        #expect(playback.accessories.card?.title == "Skipping 2 items")
        #expect(await eventually { playback.accessories.card == nil })
    }

    @Test func `the stop report goes out before the next entry's start`() async throws {
        let sent = SentReports()
        let reporting = ProgressReporting { report in
            sent.append(report)
        }
        let (playback, _) = try player(countdown: .seconds(1), others: [reporting])
        await play(playback)

        engine.send(.ended)
        await getUnderWay(loads: 2)

        #expect(await eventually { sent.lines.contains("start e2") })
        #expect(sent.lines.filter { !$0.hasPrefix("progress") } == ["start e1", "stop e1", "start e2"])
    }
}

/// The reports sent to the server, in short.
private final class SentReports: Sendable {
    private let reports = Mutex<[String]>([])

    var lines: [String] {
        reports.withLock(\.self)
    }

    func append(_ report: PlaybackReporter.Report) {
        let line = switch report {
        case let .start(stream, _): "start \(stream.itemID)"
        case let .progress(stream, _): "progress \(stream.itemID)"
        case let .stop(stream, _): "stop \(stream.itemID)"
        }
        reports.withLock { $0.append(line) }
    }
}
