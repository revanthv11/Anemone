import AnemoneJellyfin
@testable import AnemonePlayback
import Foundation
import Synchronization
import Testing

/// Up Next, autoplay and pass-out protection, driven through a controller and a fake engine.
/// `UpNextCreditsTests` has Up Next at the credits.
@MainActor
struct UpNextTests: UpNextHarness {
    let engine = FakeEngine()
    let log = EventLog()

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

    @Test func `with Never and autoplay, the next entry plays at once with no card`() async throws {
        let (playback, upNext) = try player(countdown: .seconds(100), timing: .never)
        await play(playback)
        engine.currentTime = .seconds(100)

        engine.send(.ended)

        #expect(await eventually { engine.loads.count == 2 })
        #expect(playback.queue.current.itemID == "e2")
        #expect(playback.accessories.card == nil)
        #expect(upNext.autoplaysWithoutInput == 1)
        // Straight on, with no card to count down.
        #expect(log.events.suffix(2) == ["stopped 100.0 seconds", "loaded e2 directPlay"])
    }

    @Test func `with Never and no autoplay, the player closes at the end`() async throws {
        let (playback, _) = try player(countdown: .seconds(1), autoplays: false, timing: .never)
        await play(playback)

        engine.send(.ended)

        #expect(await eventually { playback.hasEnded })
        #expect(playback.accessories.card == nil)
        try await Task.sleep(for: .milliseconds(50))
        #expect(engine.loads.count == 1)
    }

    @Test func `with Never, Still watching is still asked after enough autoplays`() async throws {
        let (playback, _) = try player(timing: .never, passOutCount: 1)
        await play(playback)
        engine.send(.ended)
        await getUnderWay(loads: 2)

        engine.send(.ended)

        #expect(await eventually { playback.accessories.card?.id == UpNext.stillWatchingCard })
    }

    @Test func `the last entry closes the player as before`() async throws {
        let (playback, _) = try player(["e1"])
        await play(playback)

        engine.send(.ended)

        #expect(await eventually { playback.hasEnded })
        #expect(playback.accessories.card == nil)
    }

    @Test func `closing the player during the countdown at the end stops it`() async throws {
        let (playback, upNext) = try player(countdown: .seconds(5))
        await play(playback)
        engine.send(.ended)
        _ = await eventually { playback.accessories.card?.id == UpNext.upNextCard }
        // The session ended with the entry, so closing brings no `stopped`.
        _ = await eventually { log.events.last == "stopped 100.0 seconds" }

        await playback.stop()

        #expect(playback.accessories.card == nil)
        // Past the end of the countdown: it didn't come back, or play anything.
        try await Task.sleep(for: .milliseconds(100))
        #expect(playback.accessories.card == nil)
        #expect(upNext.autoplaysWithoutInput == 0)
        #expect(engine.loads.count == 1)
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
        playback.feature(UpNext.self)?.creditsStarted(id: "c1")
        #expect(playback.accessories.card != nil)

        await playback.stop()

        #expect(playback.accessories.card == nil)
    }

    @Test func `a queue built without some items says so once`() async throws {
        let (playback, _) = try player(skipped: 2)
        await play(playback)

        #expect(playback.accessories.card?.id == UpNext.skippedCard)
        #expect(playback.accessories.card?.title == "Skipping 2 items")
        #expect(playback.accessories.card?.message == "Only videos play here for now.")
        #expect(await eventually { playback.accessories.card == nil })
    }

    @Test func `a queue that didn't hold everything says how much plays`() async throws {
        let (playback, _) = try player(overLimit: 30)
        await play(playback)

        #expect(playback.accessories.card?.id == UpNext.skippedCard)
        #expect(playback.accessories.card?.title == "Playing 3 of 33 items")
        #expect(playback.accessories.card?.message == "A queue holds up to 100 items.")
    }

    @Test func `the note gives every reason items were left out`() throws {
        var queue = try #require(PlaybackQueue(entries: [.item("m1"), .item("m2")]))
        queue.skippedCount = 1
        queue.overLimitCount = 30

        let note = UpNext.skippedNote(for: queue)

        #expect(note.title == "Playing 2 of 33 items")
        #expect(note.message == "A queue holds up to 100 items.\nOnly videos play here for now.")
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

/// What the Up Next tests share: a player with Up Next, a fake engine and a log of events. A
/// second of countdown takes 10 ms here.
@MainActor
protocol UpNextHarness {
    var engine: FakeEngine { get }
    var log: EventLog { get }
}

extension UpNextHarness {
    /// A player for `ids`, with `others` hearing events before the log and Up Next.
    func player(
        _ ids: [String] = ["e1", "e2", "e3"],
        skipped: Int = 0,
        overLimit: Int = 0,
        countdown: Duration = .seconds(3),
        autoplays: Bool = true,
        timing: UpNextTiming = .endOfPlayback,
        passOutCount: Int = 0,
        testCreditsStart: Duration? = nil,
        others: [any PlaybackFeature] = [],
        positionInterval: Duration = .milliseconds(10),
        streams: FakeStreams = FakeStreams(),
    ) throws -> (PlaybackController, UpNext) {
        var queue = try #require(PlaybackQueue(entries: ids.map { .item($0) }))
        queue.skippedCount = skipped
        queue.overLimitCount = overLimit
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
            positionInterval: positionInterval,
            loadStream: streams.load,
        )
        return (playback, upNext)
    }

    /// Starts playback and gets the first entry under way.
    func play(_ playback: PlaybackController) async {
        await playback.start()
        await getUnderWay(loads: 1)
    }

    /// Gets the latest entry loaded under way.
    func getUnderWay(loads: Int) async {
        _ = await eventually { engine.loads.count == loads }
        engine.send(.ready)
        _ = await eventually { log.events.count(where: { $0.hasPrefix("started") }) == loads }
    }

    func perform(_ actionID: String, on playback: PlaybackController) throws {
        let card = try #require(playback.accessories.card)
        try #require(card.actions.first { $0.id == actionID }).perform()
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
