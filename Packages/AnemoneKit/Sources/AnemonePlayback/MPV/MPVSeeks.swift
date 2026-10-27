import os

/// The MPV engine's seeks, waiting for libmpv to land them. libmpv says it started a seek with
/// a seek event and that it landed with a playback restart, but says nothing when it refuses
/// one, as on a live stream it can't seek in. So a seek it hasn't started within
/// `timeouts.start`, or hasn't landed within `timeouts.landing` after that, didn't get there,
/// rather than leaving whoever asked waiting until the next load.
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
    private var waiting: [(id: Int, done: CheckedContinuation<Bool, Never>)] = []
    private var count = 0
    private var hasStarted = false
    private var timer: Task<Void, Never>?

    init(timeouts: Timeouts = .standard, wait: @escaping Wait = { try? await Task.sleep(for: $0) }) {
        self.timeouts = timeouts
        self.wait = wait
    }

    /// Waits for the seek just sent to libmpv: `true` once it lands, `false` when a newer one
    /// replaced it or it didn't get there.
    func land() async -> Bool {
        count += 1
        let id = count
        hasStarted = false
        return await withCheckedContinuation { done in
            waiting.append((id, done))
            startTimer()
        }
    }

    /// libmpv started the newest seek, so a playback restart will follow unless the stream
    /// fails.
    func started() {
        hasStarted = true
    }

    /// Playback restarted: the newest seek got there, older ones were replaced.
    func landed() {
        finish { [count] in $0 == count }
    }

    /// The seeks waiting got there, as when one goes past the end, or didn't, as when the
    /// stream fails or stops.
    func finishAll(landed: Bool) {
        finish { _ in landed }
    }

    private func finish(_ landed: (Int) -> Bool) {
        timer?.cancel()
        timer = nil
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
