import Foundation

/// When the in-app screensaver starts, ported from Wholphin's `ScreensaverService`: once the
/// remote has been left alone for `startDelay`, unless something keeps the screen on, such as
/// playback, which counts as activity (Wholphin's `keepScreenOn` pauses the timer).
///
/// tvOS has no screensaver API for apps, so the app keeps its own idle timer and asks this what
/// to do whenever it wakes up.
public struct ScreensaverSchedule: Equatable, Sendable {
    public typealias Instant = ContinuousClock.Instant

    public enum Decision: Equatable, Sendable {
        case start
        /// Nothing to do until then.
        case wait(until: Instant)
    }

    /// How often to look again while waiting, so playback that starts or stops meanwhile is
    /// noticed.
    public static let pollInterval = Duration.seconds(30)

    public var startDelay: Duration
    public private(set) var lastActivity: Instant

    public init(startDelay: Duration, now: Instant) {
        self.startDelay = startDelay
        lastActivity = now
    }

    /// A press or touch on the remote, or the screensaver closing: the wait starts again.
    public mutating func noteActivity(at now: Instant) {
        lastActivity = now
    }

    /// Whether to start now, or when to look again.
    ///
    /// - Parameter keepsScreenOn: something on screen, such as a video, keeps the screen on.
    public mutating func check(at now: Instant, keepsScreenOn: Bool) -> Decision {
        if keepsScreenOn {
            lastActivity = now
        }
        let deadline = lastActivity + startDelay
        if now >= deadline {
            return .start
        }
        return .wait(until: min(deadline, now + Self.pollInterval))
    }
}
