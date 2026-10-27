import AnemoneCore
import Observation

/// Seeking for Anemone's overlay, through the engine, so it works the same with AVPlayer and MPV.
///
/// Steps, held presses and swipes move a `target`, which the overlay shows with a trickplay
/// thumbnail. The engine seeks there once the user stops for `commitDelay`, as Wholphin's
/// `SeekBarState` waits 750 ms, so a run of presses is one seek rather than many, which matters
/// most for a transcode the server has to restart. `commit()` seeks at once. Ported from
/// Wholphin's `SeekBar`, `SeekBarState` and the D-pad seeking in `PlaybackPage`.
@MainActor
@Observable
public final class Seeker {
    /// How long things take; tests make them short.
    public struct Timing: Sendable {
        public var commitDelay: Duration
        public var repeatDelay: Duration
        public var repeatInterval: Duration

        public init(
            commitDelay: Duration = .milliseconds(750),
            repeatDelay: Duration = SeekAcceleration.repeatDelay,
            repeatInterval: Duration = SeekAcceleration.repeatInterval,
        ) {
            self.commitDelay = commitDelay
            self.repeatDelay = repeatDelay
            self.repeatInterval = repeatInterval
        }
    }

    /// Where the user is seeking to, until the engine gets there; `nil` when not seeking.
    public private(set) var target: Duration?
    /// The engine's time and length when `refresh()` last read them.
    public private(set) var position = Duration.zero
    public private(set) var duration: Duration?
    /// Whether a left or right press is being held.
    public private(set) var isHolding = false
    public var skipBack: Duration
    public var skipForward: Duration

    @ObservationIgnored private let engine: any PlayerEngine
    @ObservationIgnored private let timing: Timing
    @ObservationIgnored private var held: HeldSeekPress?
    /// Repeats a held press; internal so tests can wait for it to end.
    @ObservationIgnored private(set) var repeating: Task<Void, Never>?
    @ObservationIgnored private var committing: Task<Void, Never>?
    /// Where the target was when the swipe began.
    @ObservationIgnored private var swipeOrigin: Duration?
    /// Counts changes to the target, so a seek that finishes after the user moved on leaves the
    /// new target alone.
    @ObservationIgnored private var changes = 0

    public init(
        engine: any PlayerEngine,
        skipBack: Duration = .milliseconds(Preferences.skipBackMs.value()),
        skipForward: Duration = .milliseconds(Preferences.skipForwardMs.value()),
        timing: Timing = Timing(),
    ) {
        self.engine = engine
        self.skipBack = skipBack
        self.skipForward = skipForward
        self.timing = timing
        refresh()
    }

    /// A press can outlive the player: it closes mid-hold and the press never ends.
    isolated deinit {
        repeating?.cancel()
        committing?.cancel()
    }

    /// What the seek bar shows: where the user is seeking to, else where playback is.
    public var shownPosition: Duration {
        target ?? position
    }

    public var isSeeking: Bool {
        target != nil
    }

    /// Reads the engine's time and length again; the overlay calls it a few times a second while
    /// something on screen shows them (`PlayerOverlay.showsPosition`).
    public func refresh() {
        position = engine.currentTime
        duration = engine.duration
    }

    /// Moves the target `steps` skips back or forward, from where it is or else from where
    /// playback is.
    public func step(_ direction: SeekDirection, steps: Int = 1) {
        guard steps > 0 else { return }
        switch direction {
        case .back: move(to: start - skipBack * steps)
        case .forward: move(to: start + skipForward * steps)
        }
        scheduleCommit()
    }

    /// A left or right press began. It seeks one step when it ends quickly; held, it seeks
    /// faster and faster until it ends. `ignoredRepeats` is
    /// `SeekAcceleration.hiddenControlsIgnoredRepeats` while the controls are hidden.
    public func pressBegan(_ direction: SeekDirection, ignoredRepeats: Int) {
        stopRepeating()
        committing?.cancel()
        held = HeldSeekPress(direction, ignoredRepeats: ignoredRepeats)
        isHolding = true
        let timing = timing
        repeating = Task { [weak self] in
            try? await Task.sleep(for: timing.repeatDelay)
            // Ends with the seeker too, should the player close mid-hold without the press ending.
            // `self?` rather than `guard let self`, so the seeker isn't kept through the sleep.
            while !Task.isCancelled, self?.repeated() != nil {
                try? await Task.sleep(for: timing.repeatInterval)
            }
        }
    }

    public func pressEnded() {
        guard let held else { return }
        stopRepeating()
        if held.stepsOnRelease > 0 {
            step(held.direction, steps: held.stepsOnRelease)
        } else {
            scheduleCommit()
        }
    }

    /// The press was taken away, by a call or the remote going to sleep: no step on release.
    public func pressCancelled() {
        guard held != nil else { return }
        stopRepeating()
        if isSeeking {
            scheduleCommit()
        }
    }

    /// A swipe across the remote's touch surface began.
    public func swipeBegan() {
        stopRepeating()
        committing?.cancel()
        swipeOrigin = start
    }

    /// The swipe moved `translation` points sideways on a surface `width` points wide.
    public func swipeMoved(translation: Double, width: Double) {
        guard let swipeOrigin else { return }
        move(to: swipeOrigin + SwipeScrubbing.offset(translation: translation, width: width, duration: duration))
    }

    public func swipeEnded() {
        guard swipeOrigin != nil else { return }
        swipeOrigin = nil
        scheduleCommit()
    }

    /// Seeks to the target now.
    public func commit() {
        stopRepeating()
        committing?.cancel()
        guard isSeeking else { return }
        committing = Task { [weak self] in
            await self?.seekToTarget()
        }
    }

    /// Stops seeking and leaves playback where it is.
    public func cancel() {
        stopRepeating()
        committing?.cancel()
        committing = nil
        swipeOrigin = nil
        changes += 1
        target = nil
    }

    /// Seeks straight to `position`, as choosing a chapter does.
    public func jump(to position: Duration) {
        stopRepeating()
        swipeOrigin = nil
        move(to: position)
        commit()
    }

    /// Where a move starts from.
    private var start: Duration {
        target ?? engine.currentTime
    }

    private func move(to position: Duration) {
        let latest = engine.duration ?? duration
        var position = max(position, .zero)
        if let latest, latest > .zero {
            position = min(position, latest)
        }
        changes += 1
        target = position
    }

    private func repeated() {
        guard var held else { return }
        let steps = held.repeated(duration: engine.duration ?? duration ?? .zero)
        self.held = held
        if let steps {
            switch held.direction {
            case .back: move(to: start - skipBack * steps)
            case .forward: move(to: start + skipForward * steps)
            }
        }
    }

    private func stopRepeating() {
        repeating?.cancel()
        repeating = nil
        held = nil
        isHolding = false
    }

    private func scheduleCommit() {
        committing?.cancel()
        guard isSeeking else { return }
        let delay = timing.commitDelay
        committing = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.seekToTarget()
        }
    }

    private func seekToTarget() async {
        guard let target, !isHolding, swipeOrigin == nil else { return }
        let change = changes
        _ = await engine.seek(to: target)
        // The user moved on while the engine was seeking: the newer target stays.
        guard change == changes else { return }
        refresh()
        self.target = nil
    }
}

/// How far a swipe across the Siri Remote's touch surface seeks while scrubbing.
public enum SwipeScrubbing {
    /// How far a swipe as wide as the overlay seeks: a fifth of the video, at least 2 and at most
    /// 10 minutes, so short videos stay precise and long ones don't take many swipes.
    public static func span(for duration: Duration?) -> Duration {
        guard let duration, duration > .zero else { return .seconds(120) }
        return min(max(duration / 5, .seconds(120)), .seconds(600))
    }

    /// The seek for a swipe that moved `translation` points on a surface `width` points wide.
    public static func offset(translation: Double, width: Double, duration: Duration?) -> Duration {
        guard width > 0, translation.isFinite else { return .zero }
        return span(for: duration) * (translation / width)
    }
}
