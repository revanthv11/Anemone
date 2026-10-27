import Foundation
#if os(tvOS) || os(iOS)
    import UIKit
#endif

/// Pauses when the app goes to the background mid-play and plays on when it comes back, as
/// Wholphin's `PlaybackLifecycleObserver` does. The play session stays open meanwhile: the
/// pause saves the position on the server, so if tvOS ends the app while it's away, Resume
/// still picks up there.
@MainActor
public final class PlaybackLifecycle: PlaybackFeature {
    public enum Change: Sendable {
        case background
        case foreground
    }

    /// The app going to and from the background.
    typealias Changes = @MainActor () -> AsyncStream<Change>
    /// Asks tvOS for a few seconds in the background, so the pause gets reported.
    typealias KeepAlive = @MainActor () -> Void

    /// Off for players that should go on in the background, such as music (Phase 5).
    public var pausesInBackground = true

    private let changes: Changes
    private let keepAlive: KeepAlive
    private weak var controller: PlaybackController?
    private var watching: Task<Void, Never>?
    private var isPlaying = false
    private var isInBackground = false
    /// Whether to play on when the app comes back.
    private var wasPlaying = false

    public convenience init() {
        #if os(tvOS) || os(iOS)
            self.init(changes: Self.appChanges, keepAlive: Self.keepAppAlive)
        #else
            self.init(changes: { AsyncStream { $0.finish() } }, keepAlive: {})
        #endif
    }

    init(changes: @escaping Changes, keepAlive: @escaping KeepAlive) {
        self.changes = changes
        self.keepAlive = keepAlive
    }

    public func handle(_ event: PlaybackEvent, in controller: PlaybackController) async {
        self.controller = controller
        switch event {
        case .loaded:
            watch()
        case .started, .resumed:
            isPlaying = true
            // Loading finished, or something played, while the app was away.
            if isInBackground {
                pause()
            }
        case .paused:
            isPlaying = false
        case .stopped:
            isPlaying = false
            wasPlaying = false
            watching?.cancel()
            watching = nil
        case .position, .ended, .failed:
            break
        }
    }

    private func watch() {
        guard watching == nil else { return }
        let changes = changes()
        watching = Task { [weak self] in
            for await change in changes {
                guard !Task.isCancelled else { return }
                self?.changed(change)
            }
        }
    }

    private func changed(_ change: Change) {
        switch change {
        case .background:
            isInBackground = true
            if isPlaying {
                pause()
            }
        case .foreground:
            isInBackground = false
            if wasPlaying {
                wasPlaying = false
                controller?.engine.play()
            }
        }
    }

    private func pause() {
        guard pausesInBackground, let controller else { return }
        wasPlaying = true
        keepAlive()
        controller.engine.pause()
    }
}

#if os(tvOS) || os(iOS)
    private extension PlaybackLifecycle {
        static func appChanges() -> AsyncStream<Change> {
            AsyncStream { continuation in
                let center = NotificationCenter.default
                let tasks = [
                    Task { @MainActor in
                        for await _ in center.notifications(named: UIApplication.didEnterBackgroundNotification) {
                            continuation.yield(.background)
                        }
                    },
                    Task { @MainActor in
                        for await _ in center.notifications(named: UIApplication.willEnterForegroundNotification) {
                            continuation.yield(.foreground)
                        }
                    },
                ]
                continuation.onTermination = { _ in
                    tasks.forEach { $0.cancel() }
                }
            }
        }

        /// Long enough for the pause report to reach the server.
        static func keepAppAlive() {
            let application = UIApplication.shared
            let time = BackgroundTime()
            time.identifier = application.beginBackgroundTask(withName: "Report the pause") {
                // tvOS calls this on the main thread when the time is up.
                MainActor.assumeIsolated { time.end() }
            }
            Task {
                try? await Task.sleep(for: .seconds(5))
                time.end()
            }
        }
    }

    /// A background task, ended once.
    @MainActor
    private final class BackgroundTime {
        var identifier = UIBackgroundTaskIdentifier.invalid

        func end() {
            guard identifier != .invalid else { return }
            UIApplication.shared.endBackgroundTask(identifier)
            identifier = .invalid
        }
    }
#endif
