import AnemoneCore
import AnemoneJellyfin
import Observation

/// What Anemone's player overlay shows, and what the remote does to it. Ported from Wholphin's
/// `PlaybackKeyHandler`, `ControllerViewState` and `PlaybackOverlay`, with Swiftfin's tvOS press
/// handling for what Android doesn't have: Select and swipes.
///
/// It knows nothing of UIKit, so it can be tested: the overlay's view controller hands it the
/// remote's presses and swipes and does what it says with the rest, and the SwiftUI view draws
/// from it. Everything it does to playback goes through the controller and its engine.
///
/// With the controls hidden, left and right seek (faster while held, with a compact seek bar and
/// thumbnails), Select or up and down show the controls, and Menu takes down a skip button over
/// the video, as Wholphin's Back does, or closes the player. With them showing, the focus engine
/// moves between buttons, left and right seek on the focused seek bar, and Menu hides them. They
/// hide on their own after `hideDelay` without a press.
@MainActor
@Observable
public final class PlayerOverlay {
    /// What the controls show, as in Wholphin: the transport, or the chapter or queue row below.
    public enum Page: Sendable {
        case controls
        case chapters
        case queue
    }

    /// The Siri Remote's buttons, as the overlay hears them.
    public enum Button: Hashable, Sendable {
        case upArrow
        case downArrow
        case leftArrow
        case rightArrow
        case select
        case menu
        case playPause
    }

    /// Where focus is, as far as presses are concerned.
    public enum Focus: Sendable {
        /// On the video: the controls are hidden.
        case video
        case seekBar
        /// On a feature's action over the video, such as Skip Intro.
        case action
        /// On the controls' button that skips the rest of the segment playing.
        case skipButton
        /// On any other button.
        case control
    }

    /// What the view controller does with a press.
    public enum Outcome: Sendable {
        case handled
        /// Left to the focus engine, which moves focus or presses the focused button.
        case passedOn
        /// Close the player.
        case close
    }

    /// Wholphin's Previous restarts the entry unless it's within this of the start.
    static let restartThreshold = Duration.seconds(3)
    /// How long the compact seek bar stays after seeking with the controls hidden, as Wholphin's.
    public static let seekBarLinger = Duration.milliseconds(1500)

    public private(set) var controlsVisible = false
    public private(set) var page = Page.controls
    public var focus = Focus.video
    /// The menu whose options are showing.
    public private(set) var openMenuID: PlayerMenu.ID?
    /// Whether the compact seek bar shows, while seeking with the controls hidden.
    public private(set) var showsSeekBar = false
    public let seeker: Seeker
    public let controller: PlaybackController
    public var hideDelay: Duration
    /// How the video fills the screen: the setting when the player opens, then what the Video
    /// scale menu picks, for this player, as Wholphin's `contentScale` lasts for its page.
    public var videoScale: VideoScale {
        didSet {
            videoScaleMenu = makeVideoScaleMenu()
        }
    }

    /// The Video scale menu, made again when the choice changes rather than at every draw.
    public private(set) var videoScaleMenu: PlayerMenu

    @ObservationIgnored private let details: PlaybackDetails?
    @ObservationIgnored private let segments: SegmentSkipping?
    /// The user's setting for a kind of segment, read each time, as `SegmentSkipping` reads it.
    @ObservationIgnored private let skipBehavior: @MainActor (MediaSegment.Kind) -> SkipSegmentBehavior
    @ObservationIgnored private let lingerDelay: Duration
    /// Presses whose start the overlay took, so it takes their end too.
    @ObservationIgnored private var claimed: Set<Button> = []
    @ObservationIgnored private var hiding: Task<Void, Never>?
    @ObservationIgnored private var seekBarHiding: Task<Void, Never>?
    @ObservationIgnored private var isSwiping = false

    public init(
        controller: PlaybackController,
        seeker: Seeker? = nil,
        hideDelay: Duration = .milliseconds(Preferences.controllerTimeoutMs.value()),
        seekBarLinger: Duration = PlayerOverlay.seekBarLinger,
        skipBehavior: @escaping @MainActor (MediaSegment.Kind) -> SkipSegmentBehavior = {
            Preferences.skipBehavior(for: $0).value()
        },
        videoScale: VideoScale = Preferences.videoScale.value(),
    ) {
        self.controller = controller
        self.seeker = seeker ?? Seeker(engine: controller.engine)
        self.hideDelay = hideDelay
        self.skipBehavior = skipBehavior
        // A choice the engine's output can't take, such as Fill saved for MPV, starts from Fit.
        self.videoScale = VideoScale.choices(for: controller.engine.videoOutput).contains(videoScale) ? videoScale : .fit
        videoScaleMenu = PlayerMenu(id: Self.videoScaleMenuID, title: "", options: [])
        lingerDelay = seekBarLinger
        details = controller.feature(PlaybackDetails.self)
        segments = controller.feature(SegmentSkipping.self)
        videoScaleMenu = makeVideoScaleMenu()
    }

    /// Paused, or not yet under way.
    public var isPaused: Bool {
        details?.isPaused ?? true
    }

    // MARK: - Presses

    public func pressBegan(_ button: Button) -> Outcome {
        pulse()
        let claims = claims(button)
        guard claims else { return .passedOn }
        claimed.insert(button)
        switch button {
        case .leftArrow, .rightArrow:
            let direction: SeekDirection = button == .leftArrow ? .back : .forward
            if !controlsVisible {
                showSeekBar()
            }
            let ignored = controlsVisible ? 0 : SeekAcceleration.hiddenControlsIgnoredRepeats
            seeker.pressBegan(direction, ignoredRepeats: ignored)
        case .upArrow, .downArrow:
            showControls()
        case .select, .menu, .playPause:
            // On release, as Swiftfin does.
            break
        }
        return .handled
    }

    public func pressEnded(_ button: Button) -> Outcome {
        guard claimed.remove(button) != nil else { return .passedOn }
        switch button {
        case .leftArrow, .rightArrow:
            seeker.pressEnded()
            lingerSeekBar()
        case .upArrow, .downArrow:
            break
        case .select:
            select()
        case .menu:
            return back()
        case .playPause:
            togglePlayPause()
        }
        return .handled
    }

    public func pressCancelled(_ button: Button) {
        guard claimed.remove(button) != nil else { return }
        if button == .leftArrow || button == .rightArrow {
            seeker.pressCancelled()
            lingerSeekBar()
        }
    }

    /// Whether the overlay takes a press, rather than the focus engine. A feature's action over
    /// the video keeps left, right and Select, as in Swiftfin; up and down still show the controls.
    private func claims(_ button: Button) -> Bool {
        let onVideo = !controlsVisible && focus != .action
        switch button {
        case .leftArrow, .rightArrow:
            return canSeek && openMenuID == nil && (onVideo || (controlsVisible && focus == .seekBar))
        case .upArrow, .downArrow:
            return !controlsVisible
        case .select:
            return onVideo || (controlsVisible && focus == .seekBar && openMenuID == nil)
        case .menu, .playPause:
            return true
        }
    }

    /// Not while the stream loads, when the engine has nowhere to seek yet.
    private var canSeek: Bool {
        if case .playing = controller.state {
            true
        } else {
            false
        }
    }

    private func select() {
        if !controlsVisible {
            // Wholphin's D-pad seek bar goes away on Select; here the seek happens at once too.
            if seeker.isSeeking {
                seeker.commit()
                lingerSeekBar()
            } else {
                showControls()
            }
        } else if seeker.isSeeking {
            seeker.commit()
        } else {
            togglePlayPause()
        }
    }

    /// Menu backs out one step at a time: the open menu, a seek, the controls, the skip button
    /// over the video, then the player.
    private func back() -> Outcome {
        if openMenuID != nil {
            closeMenu()
        } else if seeker.isSeeking {
            seeker.cancel()
            showsSeekBar = false
        } else if controlsVisible {
            hideControls()
        } else if let segments, segments.offered != nil {
            // Wholphin's Back on its skip button takes the button down for good; the controls
            // still offer to skip the rest of the segment.
            segments.dismissOffer()
        } else {
            return .close
        }
        return .handled
    }

    // MARK: - Swipes

    /// Whether a sideways swipe on the touch surface scrubs: with the controls hidden, or on the
    /// seek bar. Otherwise the focus engine moves focus with it.
    public var takesSwipes: Bool {
        canSeek && openMenuID == nil
            && ((!controlsVisible && focus != .action) || (controlsVisible && focus == .seekBar))
    }

    public func swipeBegan() {
        guard takesSwipes else { return }
        isSwiping = true
        pulse()
        if !controlsVisible {
            showSeekBar()
        }
        seeker.swipeBegan()
    }

    /// The swipe has moved `translation` points sideways on a surface `width` points wide.
    public func swipeMoved(translation: Double, width: Double) {
        guard isSwiping else { return }
        pulse()
        seeker.swipeMoved(translation: translation, width: width)
    }

    public func swipeEnded() {
        guard isSwiping else { return }
        isSwiping = false
        seeker.swipeEnded()
        lingerSeekBar()
    }

    // MARK: - Controls

    public func showControls() {
        if !showsPosition {
            // Nothing has read the position while nothing showed it.
            seeker.refresh()
        }
        controlsVisible = true
        page = .controls
        showsSeekBar = false
        pulse()
    }

    public func hideControls() {
        controlsVisible = false
        openMenuID = nil
        page = .controls
        hiding?.cancel()
        hiding = nil
    }

    /// Shows a row below the transport, when focus moves to it.
    public func show(_ page: Page) {
        guard controlsVisible else { return }
        self.page = page
        pulse()
    }

    public func openMenu(_ id: PlayerMenu.ID) {
        openMenuID = id
        pulse()
    }

    public func closeMenu() {
        openMenuID = nil
        pulse()
    }

    /// Keeps the controls up for another `hideDelay`, as Wholphin's `pulseControls`.
    public func pulse() {
        hiding?.cancel()
        guard controlsVisible else { return }
        let delay = hideDelay
        hiding = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.hideIfIdle()
        }
    }

    private func hideIfIdle() {
        // Not from under an open menu or a seek still being chosen.
        if openMenuID != nil || seeker.isHolding || isSwiping || (focus == .seekBar && seeker.isSeeking) {
            pulse()
        } else {
            hideControls()
        }
    }

    private func lingerSeekBar() {
        seekBarHiding?.cancel()
        guard showsSeekBar else { return }
        let delay = lingerDelay
        seekBarHiding = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            if seeker.isSeeking || seeker.isHolding || isSwiping {
                lingerSeekBar()
            } else {
                showsSeekBar = false
            }
        }
    }
}

/// What the overlay shows besides the controls.
public extension PlayerOverlay {
    /// Whether anything on screen shows where playback is: the controls, or the compact seek bar.
    /// The overlay reads the engine's position only while it does, rather than all through
    /// playback.
    var showsPosition: Bool {
        controlsVisible || showsSeekBar
    }

    /// The segment playing, for the skip button in Wholphin's controls, which skips the rest of
    /// it: a kind the user doesn't ignore, once `SegmentSkipping`'s own button has gone. While
    /// that one shows, it's among the controls' actions.
    var skippableSegment: MediaSegment? {
        guard let segments, let segment = segments.current, segments.offered != segment,
              skipBehavior(segment.kind) != .ignore
        else { return nil }
        return segment
    }

    /// Whether focus should move to Play/Pause: the controls' skip button had it, and has gone as
    /// its segment ended, which would leave focus nowhere. Pressing the button moves focus there
    /// before it goes.
    var skipButtonLeftFocus: Bool {
        controlsVisible && focus == .skipButton && skippableSegment == nil
    }

    /// Another entry is playing, such as the movie after its cinema pre-roll. A seek still being
    /// chosen was along the entry before, so it's dropped, with the compact seek bar showing it,
    /// and a press still held seeks no more: landing at that time in the new entry isn't what the
    /// presses asked for. Wholphin's seek lands there all the same, once its 750 ms wait is up;
    /// after a pre-roll, that's a few seconds into the movie, since the seek stops at the end of
    /// the pre-roll.
    func entryChanged() {
        seeker.cancel()
        seekBarHiding?.cancel()
        showsSeekBar = false
    }

    /// The compact seek bar, while seeking with the controls hidden.
    private func showSeekBar() {
        if !showsPosition {
            // Nothing has read the position, or the length a swipe scrubs by, while nothing showed
            // them.
            seeker.refresh()
        }
        showsSeekBar = true
    }
}
