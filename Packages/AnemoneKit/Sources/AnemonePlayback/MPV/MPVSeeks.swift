import os

/// The MPV engine's seeks, waiting for libmpv to land them. libmpv says it started a seek with
/// a seek event and that it landed with a playback restart, but says nothing when it can't do
/// one, as on a live stream it can't seek in. So a seek it hasn't started within
/// `timeouts.start`, or hasn't landed within `timeouts.landing` after that, didn't get there,
/// rather than leaving whoever asked waiting until the next load.
///
/// libmpv's seek events don't say which seek they're for, and one for an older seek can still be
/// on its way when a newer one is sent. Seeks go to libmpv with `commandAsync`, whose reply
/// comes before libmpv starts the seek: so a seek event belongs to the newest seek only once
/// that seek's reply has come, and a playback restart only once that seek has started.
@MainActor
final class MPVSeeks {
    struct Timeouts: Sendable {
        /// libmpv starts a seek it takes at once, so this only allows for the event's way here.
        var start: Duration
        /// Long enough to fetch the new position over a slow connection.
        var landing: Duration

        static let standard = Self(start: .seconds(2), landing: .seconds(20))
    }

    /// Waits for a timeout; tests stand in their own, so a timeout passes when they say.
    typealias Wait = @MainActor @Sendable (Duration) async -> Void

    private let timeouts: Timeouts
    private let wait: Wait
    /// Newest last. A newer seek replaces older ones.
    private var waiting: [(id: UInt64, done: CheckedContinuation<Bool, Never>)] = []
    /// The newest seek sent, which libmpv's replies and events are matched against.
    private var newest: UInt64 = 0
    /// libmpv has replied that it took the newest seek, so seek events from now on are its own.
    private var isTaken = false
    private var hasStarted = false
    private var timer: Task<Void, Never>?

    init(timeouts: Timeouts = .standard, wait: @escaping Wait = { try? await Task.sleep(for: $0) }) {
        self.timeouts = timeouts
        self.wait = wait
    }

    /// Sends a seek with `send`, which is given the seek's ID for libmpv's reply and says whether
    /// libmpv queued it, then waits for it: `true` once it lands, `false` when libmpv refused it,
    /// a newer one replaced it, or it didn't get there.
    func land(sending send: (UInt64) -> Bool) async -> Bool {
        let id = newest + 1
        guard send(id) else { return false }
        newest = id
        isTaken = false
        hasStarted = false
        return await withCheckedContinuation { done in
            waiting.append((id, done))
            startTimer()
        }
    }

    /// libmpv's reply to seek `id`: it took it, so if it's the newest the next seek event is its
    /// own, or it refused it, as with nothing loaded to seek in.
    func replied(_ id: UInt64, succeeded: Bool) {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else { return }
        if succeeded {
            isTaken = isTaken || id == newest
        } else if id == newest {
            finishAll(landed: false)
        } else {
            waiting.remove(at: index).done.resume(returning: false)
        }
    }

    /// libmpv started a seek: the newest one, once libmpv has taken it. One before that is an
    /// older seek's, which doesn't put the newest on the landing timeout.
    func started() {
        hasStarted = hasStarted || isTaken
    }

    /// Playback restarted: once the newest seek has started, it got there and older ones were
    /// replaced. A restart before that is an older seek's.
    func landed() {
        guard hasStarted else { return }
        finish { [newest] in $0 == newest }
    }

    /// The seeks waiting got there, as when one goes past the end, or didn't, as when the
    /// stream fails or stops.
    func finishAll(landed: Bool) {
        finish { _ in landed }
    }

    private func finish(_ landed: (UInt64) -> Bool) {
        timer?.cancel()
        timer = nil
        isTaken = false
        hasStarted = false
        let seeks = waiting
        waiting = []
        for seek in seeks {
            seek.done.resume(returning: landed(seek.id))
        }
    }

    private func startTimer() {
        timer?.cancel()
        timer = Task { [weak self, wait, timeouts] in
            await wait(timeouts.start)
            guard !Task.isCancelled, let started = self?.hasStarted else { return }
            if started {
                await wait(timeouts.landing)
                guard !Task.isCancelled else { return }
            }
            Logger.mpv.info("seek gave up: \(started ? "it didn't land" : "libmpv didn't start it", privacy: .public)")
            self?.finishAll(landed: false)
        }
    }
}
