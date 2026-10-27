/// How holding left or right speeds seeking up. Ported from Wholphin's `SeekAcceleration.kt`
/// and the hold handling in `PlaybackKeyHandler` and `SeekBar`.
///
/// Android repeats a held key, and Wholphin seeks once per repeat by a step that grows the longer
/// the key is held and the longer the video. The Siri Remote doesn't repeat presses, so the
/// overlay repeats them itself, from when a press begins until it ends, at Android's pace:
/// after `repeatDelay`, every `repeatInterval`.
public enum SeekAcceleration {
    public static let repeatDelay = Duration.milliseconds(500)
    public static let repeatInterval = Duration.milliseconds(50)
    /// Repeats Wholphin lets pass before seeking while the controls are hidden, so a slightly long
    /// press is still one step. On the seek bar every repeat seeks.
    public static let hiddenControlsIgnoredRepeats = 8

    /// How many steps one repeat seeks, after `repeatCount` repeats of a video `duration` long.
    public static func multiplier(repeatCount: Int, duration: Duration) -> Int {
        guard repeatCount > 0, duration > .zero else { return 1 }
        // Wholphin: "Repeat cadence varies by device. Scaling down by 3 keeps ramp-up closer to
        // multi-second holds."
        let scaled = repeatCount / 3
        let minutes = Int(duration / .seconds(60))
        let steps = tiers.first { minutes < $0.shorterThan }?.steps ?? []
        return steps.last { scaled >= $0.from }?.multiplier ?? 1
    }

    /// Wholphin's tiers: for videos shorter than so many minutes, the multiplier from each scaled
    /// repeat count on; 1 before the first.
    private static let tiers: [(shorterThan: Int, steps: [(from: Int, multiplier: Int)])] = [
        (30, [(30, 2)]),
        (90, [(13, 2), (50, 3), (75, 4)]),
        (150, [(20, 2), (40, 4), (60, 6)]),
        (.max, [(20, 3), (40, 6), (60, 10)]),
    ]
}

/// Which way a seek goes.
public enum SeekDirection: Sendable {
    case back
    case forward
}

/// One held left or right press: counts the repeats and says how many steps each seeks, as
/// Wholphin's key handler does with Android's repeat count.
public struct HeldSeekPress: Sendable {
    public let direction: SeekDirection
    /// `SeekAcceleration.hiddenControlsIgnoredRepeats` while the controls are hidden, 0 on the
    /// seek bar.
    public let ignoredRepeats: Int
    public private(set) var repeats = 0
    /// Whether a repeat has seeked, so letting go doesn't seek again.
    public private(set) var seekedOnRepeat = false

    public init(_ direction: SeekDirection, ignoredRepeats: Int) {
        self.direction = direction
        self.ignoredRepeats = ignoredRepeats
    }

    /// Counts a repeat, returning how many steps it seeks, or `nil` while repeats are still let
    /// pass.
    public mutating func repeated(duration: Duration) -> Int? {
        repeats += 1
        guard repeats >= max(ignoredRepeats, 1) else { return nil }
        seekedOnRepeat = true
        return SeekAcceleration.multiplier(repeatCount: repeats - ignoredRepeats, duration: duration)
    }

    /// Steps to seek when the press ends: one, unless repeats already seeked.
    public var stepsOnRelease: Int {
        seekedOnRepeat ? 0 : 1
    }
}
