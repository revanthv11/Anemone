import AnemoneJellyfin
@testable import AnemonePlayback
import Foundation
import Synchronization
import Testing

/// Anemone's overlay: what the remote does with the controls hidden and showing, and what the
/// overlay learns from the controller.
@MainActor
struct PlayerOverlayTests {
    private let engine = FakeEngine()
    private let previewRequests = PreviewRequests()

    private func controller(_ entries: [PlaybackQueue.Entry] = [.item("m1")]) throws -> PlaybackController {
        let requests = previewRequests
        let details = PlaybackDetails { itemID, mediaSourceID in
            requests.list.withLock { $0.append("\(itemID) \(mediaSourceID ?? "-")") }
            return SeekPreviews(chapters: [Chapter(index: 0, name: "Start", start: .zero)])
        }
        return try PlaybackController(
            request: PlaybackRequest(queue: #require(PlaybackQueue(entries: entries))),
            engine: engine,
            features: [details],
            positionInterval: .milliseconds(10),
            loadStream: FakeStreams().load,
        )
    }

    private func overlay(_ playback: PlaybackController, hideDelay: Duration = .seconds(60)) -> PlayerOverlay {
        PlayerOverlay(
            controller: playback,
            seeker: Seeker(
                engine: engine,
                skipBack: .seconds(10),
                skipForward: .seconds(30),
                timing: Seeker.Timing(commitDelay: .seconds(60)),
            ),
            hideDelay: hideDelay,
            seekBarLinger: .milliseconds(20),
        )
    }

    /// Starts `playback` and lets the engine get it under way.
    private func play(_ playback: PlaybackController) async throws {
        await playback.start()
        engine.send(.ready)
        let details = try #require(playback.feature(PlaybackDetails.self))
        #expect(await eventually { !details.isPaused })
    }

    private func tap(_ button: PlayerOverlay.Button, on overlay: PlayerOverlay) -> PlayerOverlay.Outcome {
        _ = overlay.pressBegan(button)
        return overlay.pressEnded(button)
    }

    @Test func `with the controls hidden, left and right seek with a compact seek bar`() async throws {
        let playback = try controller()
        try await play(playback)
        engine.currentTime = .seconds(40)
        let overlay = overlay(playback)

        #expect(overlay.pressBegan(.rightArrow) == .handled)
        #expect(overlay.showsSeekBar)
        #expect(overlay.pressEnded(.rightArrow) == .handled)
        #expect(overlay.seeker.target == .seconds(70))
        #expect(tap(.leftArrow, on: overlay) == .handled)
        #expect(overlay.seeker.target == .seconds(60))
        #expect(!overlay.controlsVisible)

        // Select seeks at once, and the bar goes once it's done.
        #expect(tap(.select, on: overlay) == .handled)
        #expect(await eventually { engine.currentTime == .seconds(60) })
        #expect(!overlay.controlsVisible)
        #expect(await eventually { !overlay.showsSeekBar })
    }

    @Test func `pressing Select or up shows the controls, and Menu backs out one step at a time`() async throws {
        let playback = try controller()
        try await play(playback)
        let overlay = overlay(playback)

        #expect(tap(.select, on: overlay) == .handled)
        #expect(overlay.controlsVisible)
        #expect(tap(.menu, on: overlay) == .handled)
        #expect(!overlay.controlsVisible)
        #expect(tap(.upArrow, on: overlay) == .handled)
        #expect(overlay.controlsVisible)

        overlay.openMenu("audio")
        #expect(tap(.menu, on: overlay) == .handled)
        #expect(overlay.openMenuID == nil)
        #expect(overlay.controlsVisible)
        #expect(tap(.menu, on: overlay) == .handled)
        #expect(tap(.menu, on: overlay) == .close)
    }

    @Test func `pressing Menu drops a seek before anything else`() async throws {
        let playback = try controller()
        try await play(playback)
        let overlay = overlay(playback)

        _ = tap(.rightArrow, on: overlay)
        #expect(overlay.seeker.isSeeking)
        #expect(tap(.menu, on: overlay) == .handled)

        #expect(!overlay.seeker.isSeeking)
        #expect(!overlay.showsSeekBar)
        #expect(engine.currentTime == .zero)
    }

    @Test func `with the controls showing, presses move focus except on the seek bar`() async throws {
        let playback = try controller()
        try await play(playback)
        engine.currentTime = .seconds(50)
        let overlay = overlay(playback)
        overlay.showControls()

        overlay.focus = .control
        #expect(overlay.pressBegan(.leftArrow) == .passedOn)
        #expect(overlay.pressEnded(.leftArrow) == .passedOn)
        #expect(tap(.downArrow, on: overlay) == .passedOn)
        #expect(tap(.select, on: overlay) == .passedOn)
        #expect(!overlay.takesSwipes)
        #expect(!overlay.seeker.isSeeking)

        overlay.focus = .seekBar
        #expect(overlay.takesSwipes)
        #expect(tap(.leftArrow, on: overlay) == .handled)
        #expect(overlay.seeker.target == .seconds(40))
        #expect(!overlay.showsSeekBar)
        #expect(tap(.select, on: overlay) == .handled)
        #expect(await eventually { engine.currentTime == .seconds(40) })
        #expect(overlay.controlsVisible)
    }

    @Test func `pressing Select on the seek bar plays and pauses, as does Play/Pause`() async throws {
        let playback = try controller()
        try await play(playback)
        let overlay = overlay(playback)
        let details = try #require(playback.feature(PlaybackDetails.self))
        overlay.showControls()
        overlay.focus = .seekBar

        #expect(tap(.select, on: overlay) == .handled)
        #expect(!engine.isPlaying)
        #expect(await eventually { details.isPaused })
        #expect(overlay.isPaused)

        #expect(tap(.playPause, on: overlay) == .handled)
        #expect(engine.isPlaying)
        #expect(await eventually { !details.isPaused })
    }

    @Test func `a feature's action over the video keeps left, right and Select`() async throws {
        let playback = try controller()
        try await play(playback)
        let overlay = overlay(playback)
        overlay.focus = .action

        #expect(tap(.rightArrow, on: overlay) == .passedOn)
        #expect(tap(.select, on: overlay) == .passedOn)
        #expect(!overlay.takesSwipes)
        #expect(!overlay.seeker.isSeeking)
        #expect(!overlay.controlsVisible)

        #expect(tap(.downArrow, on: overlay) == .handled)
        #expect(overlay.controlsVisible)
    }

    @Test func `nothing seeks while the stream loads`() throws {
        let playback = try controller()
        let overlay = overlay(playback)

        #expect(tap(.rightArrow, on: overlay) == .passedOn)
        #expect(!overlay.takesSwipes)
        #expect(!overlay.seeker.isSeeking)
    }

    @Test func `the controls hide on their own, but not from under an open menu`() async throws {
        let playback = try controller()
        try await play(playback)
        let overlay = overlay(playback, hideDelay: .milliseconds(30))

        overlay.showControls()
        overlay.openMenu("speed")
        try await Task.sleep(for: .milliseconds(100))
        #expect(overlay.controlsVisible)

        overlay.closeMenu()
        #expect(await eventually { !overlay.controlsVisible })
    }

    @Test func `a swipe with the controls hidden scrubs`() async throws {
        let playback = try controller()
        try await play(playback)
        engine.currentTime = .seconds(10)
        let overlay = overlay(playback)
        overlay.seeker.refresh()

        #expect(overlay.takesSwipes)
        overlay.swipeBegan()
        #expect(overlay.showsSeekBar)
        overlay.swipeMoved(translation: 960, width: 1920)
        overlay.swipeEnded()

        // Even a 100 s video scrubs 2 minutes a swipe, so half a swipe is a minute.
        #expect(overlay.seeker.target == .seconds(70))
    }

    @Test func `previous restarts this entry, and next and the queue row play others`() async throws {
        let playback = try controller([.item("m1"), .item("m2")])
        try await play(playback)
        engine.currentTime = .seconds(30)
        let overlay = overlay(playback)
        overlay.showControls()

        overlay.previous()
        #expect(await eventually { engine.currentTime == .zero })
        #expect(playback.queue.currentIndex == 0)

        #expect(overlay.hasNext)
        overlay.next()
        #expect(!overlay.controlsVisible)
        #expect(await eventually { engine.loads.count == 2 })
        #expect(playback.queue.currentIndex == 1)
        #expect(!overlay.hasNext)

        overlay.previous()
        #expect(await eventually { engine.loads.count == 3 })
        #expect(playback.queue.currentIndex == 0)
    }

    @Test func `choosing a chapter jumps there and hides the controls`() async throws {
        let playback = try controller()
        try await play(playback)
        let overlay = overlay(playback)
        overlay.showControls()
        overlay.show(.chapters)
        #expect(overlay.page == .chapters)

        overlay.jump(to: Chapter(index: 2, name: "Third", start: .seconds(75)))

        #expect(!overlay.controlsVisible)
        #expect(overlay.page == .controls)
        #expect(await eventually { engine.currentTime == .seconds(75) })
    }

    @Test func `previews are fetched once the overlay asks, for each new entry`() async throws {
        let playback = try controller([.item("m1"), .item("m2")])
        try await play(playback)
        let details = try #require(playback.feature(PlaybackDetails.self))
        try await Task.sleep(for: .milliseconds(30))
        #expect(previewRequests.list.withLock(\.self).isEmpty)
        #expect(details.stream?.itemID == "m1")

        details.loadSeekPreviews()
        #expect(await eventually { details.previews != nil })
        #expect(details.previews?.chapters.map(\.name) == ["Start"])
        details.loadSeekPreviews()

        playback.playNext()
        #expect(await eventually { previewRequests.list.withLock(\.count) == 2 })
        #expect(previewRequests.list.withLock(\.self) == ["m1 src-m1", "m2 src-m2"])
        #expect(await eventually { details.previews != nil })
        #expect(details.entry?.itemID == "m2")
    }

    @Test func `a transcode retry keeps the previews`() async throws {
        let playback = try controller()
        try await play(playback)
        let details = try #require(playback.feature(PlaybackDetails.self))
        details.loadSeekPreviews()
        #expect(await eventually { details.previews != nil })

        engine.send(.failed(PlayerError.streamFailed(underlying: nil)))
        #expect(await eventually { details.stream?.method == .transcode })

        #expect(details.previews != nil)
        #expect(previewRequests.list.withLock(\.count) == 1)
        #expect(details.isPaused)
    }
}

/// The previews the fake server was asked for.
private final class PreviewRequests: Sendable {
    let list = Mutex<[String]>([])
}
