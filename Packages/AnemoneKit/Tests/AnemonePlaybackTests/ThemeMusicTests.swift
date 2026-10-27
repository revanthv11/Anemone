import AnemoneCore
import AnemoneJellyfin
@testable import AnemonePlayback
import Foundation
import Synchronization
import Testing

/// Theme music on item pages: which song plays when, and how videos hold it back.
@MainActor
struct ThemeMusicTests {
    private let output = FakeThemeOutput()
    private let finder = FakeThemeFinder()
    private let page = UUID()
    private let otherPage = UUID()

    private func music(volume: ThemeMusicVolume = .medium) -> ThemeMusic {
        ThemeMusic(output: output) { volume }
    }

    @Test func `a page plays its item's theme at the volume chosen`() async {
        let music = music(volume: .high)

        music.show("m1", for: page, find: finder.find)

        #expect(await eventually { output.played.count == 1 })
        #expect(output.played.first?.url == FakeThemeFinder.url("m1"))
        #expect(output.played.first?.volume == 0.5)
        #expect(finder.asked == ["m1"])
    }

    @Test func `the highest volume is three quarters, not Wholphin's 75 times full`() {
        #expect(ThemeMusicVolume.highest.level == 0.75)
        #expect(ThemeMusicVolume.allCases.compactMap(\.level).allSatisfy { $0 > 0 && $0 <= 1 })
        #expect(ThemeMusicVolume.disabled.level == nil)
        #expect(Preferences.playThemeSongs.defaultValue == .medium)
    }

    @Test func `with theme music off, nothing is looked up or played`() async throws {
        let music = music(volume: .disabled)

        music.show("m1", for: page, find: finder.find)
        try await Task.sleep(for: .milliseconds(50))

        #expect(finder.asked.isEmpty)
        #expect(output.played.isEmpty)
    }

    @Test func `the same theme carries on from a series to its season`() async throws {
        let music = music()
        music.show("series1", for: page, find: finder.find)
        #expect(await eventually { output.played.count == 1 })

        music.show("series1", for: otherPage, find: finder.find)
        music.hide(page)
        try await Task.sleep(for: .milliseconds(50))

        #expect(output.played.count == 1)
        #expect(output.stops == 0)
        #expect(finder.asked == ["series1"])
    }

    @Test func `another item's page starts its own theme`() async {
        let music = music()
        music.show("m1", for: page, find: finder.find)
        #expect(await eventually { output.played.count == 1 })

        music.show("m2", for: otherPage, find: finder.find)

        #expect(await eventually { output.played.count == 2 })
        #expect(output.played.last?.url == FakeThemeFinder.url("m2"))
        #expect(output.stops == 1)
    }

    @Test func `leaving the page stops its theme`() async {
        let music = music()
        music.show("m1", for: page, find: finder.find)
        #expect(await eventually { output.played.count == 1 })

        music.hide(page)

        #expect(output.stops == 1)
        #expect(music.playing == nil)
    }

    @Test func `a page that's no longer showing can't stop the next page's theme`() async {
        let music = music()
        music.show("m1", for: page, find: finder.find)
        music.show("m2", for: otherPage, find: finder.find)
        #expect(await eventually { output.played.count == 1 })

        music.hide(page)

        #expect(music.playing == "m2")
        #expect(output.played.map(\.url) == [FakeThemeFinder.url("m2")])
    }

    @Test func `a page left before its theme is found plays nothing`() async throws {
        let slow = FakeThemeFinder(delay: .milliseconds(50))
        let music = music()

        music.show("m1", for: page, find: slow.find)
        music.hide(page)
        try await Task.sleep(for: .milliseconds(100))

        #expect(output.played.isEmpty)
    }

    @Test func `an item without a theme plays nothing`() async throws {
        let music = music()

        music.show("m1", for: page) { _ in nil }
        try await Task.sleep(for: .milliseconds(50))

        #expect(output.played.isEmpty)
    }

    @Test func `a video player holds the theme back until it closes, then the page plays it again`() async throws {
        let music = music()
        music.show("m1", for: page, find: finder.find)
        #expect(await eventually { output.played.count == 1 })
        let playback = try player(["m1"], engine: FakeEngine(), music: music, log: EventLog())

        #expect(output.stops == 1)
        // The app coming back to the foreground under the player shows the page again.
        music.hide(page)
        music.show("m1", for: page, find: finder.find)
        #expect(music.playing == nil)

        await playback.stop()

        #expect(await eventually { output.played.count == 2 })
    }

    @Test func `a page that opens under a player waits for it to close`() async throws {
        let music = music()
        let playback = try player(["m1"], engine: FakeEngine(), music: music, log: EventLog())

        // A link opens the item's page with its player over it.
        music.show("m1", for: page, find: finder.find)
        try await Task.sleep(for: .milliseconds(50))
        #expect(output.played.isEmpty)

        await playback.stop()

        #expect(await eventually { output.played.count == 1 })
    }

    @Test func `a player that went away without closing holds nothing back`() async throws {
        let music = music()
        do {
            let playback = try player(["m1"], engine: FakeEngine(), music: music, log: EventLog())
            #expect(music.isHeldForVideo)
            _ = playback
        }

        music.show("m1", for: page, find: finder.find)

        #expect(await eventually { output.played.count == 1 })
    }

    @Test func `the theme stops as soon as the player opens, before intros or the stream load`() async throws {
        let music = music()
        music.show("m1", for: page, find: finder.find)
        #expect(await eventually { output.played.count == 1 })
        let engine = FakeEngine()
        let lookingForIntros = Mutex(false)
        let playback = try PlaybackController(
            request: PlaybackRequest(
                queue: #require(PlaybackQueue(entries: [.item("m1")])),
                intros: { _ in
                    lookingForIntros.withLock { $0 = true }
                    try await Task.sleep(for: .milliseconds(100))
                    return []
                },
            ),
            engine: engine,
            features: [],
            loadStream: FakeStreams().load,
        )

        music.hold(while: playback)
        #expect(output.stops == 1)
        #expect(music.playing == nil)
        let start = Task { await playback.start() }
        #expect(await eventually { lookingForIntros.withLock(\.self) })
        #expect(output.played.count == 1)
        await start.value
        #expect(engine.loads.count == 1)
        #expect(music.isHeldForVideo)

        await playback.stop()

        #expect(!music.isHeldForVideo)
        #expect(await eventually { output.played.count == 2 })
    }

    @Test func `the end of the queue lets the theme play again once the player has closed`() async throws {
        let music = music()
        music.show("m1", for: page, find: finder.find)
        #expect(await eventually { output.played.count == 1 })
        let engine = FakeEngine()
        let log = EventLog()
        let playback = try player(["m1"], engine: engine, music: music, log: log)
        await playback.start()
        engine.send(.ready)

        engine.send(.ended)
        #expect(await eventually { playback.hasEnded && log.events.last?.hasPrefix("stopped") == true })
        // The last frame is still on screen.
        #expect(music.isHeldForVideo)
        // The player screen dismisses at the end, and stops the controller as it goes.
        await playback.stop()

        #expect(!music.isHeldForVideo)
        #expect(await eventually { output.played.count == 2 })
    }

    @Test func `cancelling Up Next at the end lets the theme play again once the player has closed`() async throws {
        let music = music()
        music.show("e1", for: page, find: finder.find)
        #expect(await eventually { output.played.count == 1 })
        let engine = FakeEngine()
        let log = EventLog()
        let playback = try player(["e1", "e2"], engine: engine, music: music, log: log, upNext: true)
        await playback.start()
        engine.send(.ready)
        engine.send(.ended)
        // The first entry's session ended while the card counts down over its last frame.
        #expect(await eventually { log.events.last?.hasPrefix("stopped") == true })
        let card = try #require(playback.accessories.card)
        #expect(card.id == UpNext.upNextCard)

        try #require(card.actions.first { $0.id == "upNext.cancel" }).perform()
        #expect(playback.hasEnded)
        #expect(music.isHeldForVideo)
        // The player screen dismisses at the end, and stops the controller as it goes.
        await playback.stop()

        #expect(!music.isHeldForVideo)
        #expect(await eventually { output.played.count == 2 })
        #expect(engine.loads.count == 1)
    }

    @Test func `closing the player during Up Next's countdown lets the theme play again`() async throws {
        let music = music()
        music.show("e1", for: page, find: finder.find)
        #expect(await eventually { output.played.count == 1 })
        let engine = FakeEngine()
        let log = EventLog()
        let playback = try player(["e1", "e2"], engine: engine, music: music, log: log, upNext: true)
        await playback.start()
        engine.send(.ready)
        engine.send(.ended)
        #expect(await eventually { log.events.last?.hasPrefix("stopped") == true })
        #expect(playback.accessories.card?.id == UpNext.upNextCard)

        // Back on the remote.
        await playback.stop()

        #expect(!music.isHeldForVideo)
        #expect(await eventually { output.played.count == 2 })
    }

    @Test func `a stream the server won't offer keeps the theme stopped until the error is dismissed`() async throws {
        let music = music()
        music.show("m1", for: page, find: finder.find)
        #expect(await eventually { output.played.count == 1 })
        let playback = try PlaybackController(
            request: PlaybackRequest(queue: #require(PlaybackQueue(entries: [.item("m1")]))),
            engine: FakeEngine(),
            features: [],
            loadStream: FakeStreams(failingWith: PlaybackError.notAllowed).load,
        )
        music.hold(while: playback)

        await playback.start()

        // The player shows the error over the page.
        guard case .failed = playback.state else {
            Issue.record("The player should show the error")
            return
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(music.isHeldForVideo)
        #expect(output.played.count == 1)
        #expect(output.stops == 1)

        await playback.stop()

        #expect(await eventually { output.played.count == 2 })
    }

    /// A player for `ids` that holds `music` back from now, as the app's players do, with Up Next
    /// if asked (counting down for long enough that it never plays the next entry on its own), and
    /// `log` hearing events last.
    private func player(
        _ ids: [String],
        engine: FakeEngine,
        music: ThemeMusic,
        log: EventLog,
        upNext: Bool = false,
    ) throws -> PlaybackController {
        var features: [any PlaybackFeature] = [log]
        if upNext {
            let settings = UpNext.Settings(countdown: .seconds(100), passOutCount: 0)
            features.insert(UpNext(settings: settings, second: .milliseconds(10)), at: 0)
        }
        let playback = try PlaybackController(
            request: PlaybackRequest(queue: #require(PlaybackQueue(entries: ids.map { .item($0) }))),
            engine: engine,
            features: features,
            loadStream: FakeStreams().load,
        )
        music.hold(while: playback)
        return playback
    }
}

extension ThemeMusicTests {
    @Test func `a player dropped without closing lets the page showing play its theme again`() async throws {
        let music = music()
        music.show("m1", for: page, find: finder.find)
        #expect(await eventually { output.played.count == 1 })
        weak var dropped: PlaybackController?
        do {
            let playback = try player(["m1"], engine: FakeEngine(), music: music, log: EventLog())
            dropped = playback
            #expect(output.stops == 1)
            #expect(music.playing == nil)
        }

        // Nothing calls stop(), and the page doesn't show again.
        #expect(dropped == nil)
        #expect(await eventually { output.played.count == 2 })
        #expect(music.playing == "m1")
    }
}

/// Records the songs it's asked to play.
@MainActor
final class FakeThemeOutput: ThemeMusicOutput {
    struct Played: Equatable {
        let url: URL
        let volume: Float
    }

    private(set) var played: [Played] = []
    private(set) var stops = 0

    func play(_ url: URL, volume: Float) {
        played.append(Played(url: url, volume: volume))
    }

    func stop() {
        stops += 1
    }
}

/// Finds a song for every item, after `delay`.
final class FakeThemeFinder: Sendable {
    private let requests = Mutex<[MediaItem.ID]>([])
    private let delay: Duration

    init(delay: Duration = .zero) {
        self.delay = delay
    }

    var asked: [MediaItem.ID] {
        requests.withLock(\.self)
    }

    var find: ThemeMusic.Finder {
        { [self] itemID in
            requests.withLock { $0.append(itemID) }
            try await Task.sleep(for: delay)
            return Self.url(itemID)
        }
    }

    static func url(_ itemID: MediaItem.ID) -> URL {
        URL(filePath: "/themes/\(itemID).mp3")
    }
}
