import AnemoneCore
import AnemoneJellyfin
import Foundation
import Observation

public extension Preferences {
    /// Wholphin's `slideshowDuration`: how long each photo shows in a slideshow, in
    /// milliseconds, from 1 to 30 seconds; 5 seconds by default.
    static let slideshowDuration = Preference("slideshowDuration", default: 5000)
    /// Wholphin's "Play videos during slideshow" (`slideshowPlayVideos`): clips in an album play
    /// in the slideshow, or are left out of it. Off by default.
    static let slideshowPlayVideos = Preference("slideshowPlayVideos", default: false)
}

/// A photo viewer that runs as a slideshow, ported from Wholphin's `SlideshowViewModel`. Left
/// and right move through the photos. As a slideshow, it moves on by itself once a photo has
/// shown for the set time, counted from when it finished loading, and goes back to the first
/// after the last; a clip plays to its end before the time starts. Showing the details pauses
/// it.
@MainActor
@Observable
public final class Slideshow {
    /// Wholphin's limits for the time each photo shows.
    public static let durationRange = 1000 ... 30000

    public let pager: SlideshowPager
    /// The photo showing, or about to once its page loads.
    public private(set) var position = 0
    /// Wholphin's slideshow mode: whether it moves on by itself.
    public private(set) var isRunning = false
    /// Held while the details show.
    public private(set) var isPaused = false
    @ObservationIgnored private let delay: Duration
    @ObservationIgnored private var timer: Task<Void, Never>?

    public init(pager: SlideshowPager, delay: Duration) {
        self.pager = pager
        self.delay = delay
    }

    /// How long each photo shows, from the user's setting within Wholphin's limits.
    public static func delay(in defaults: UserDefaults = .standard) -> Duration {
        let milliseconds = Preferences.slideshowDuration.value(in: defaults)
        return .milliseconds(durationRange.contains(milliseconds) ? milliseconds : 5000)
    }

    public var current: SlideshowItem? {
        pager.item(at: position)
    }

    /// Moving on by itself now: running and not paused.
    public var isActive: Bool {
        isRunning && !isPaused
    }

    /// Loads the first page and goes to the photo picked, if it's there; otherwise the first.
    ///
    /// - Parameter hint: where the photo was in the grid it was picked from.
    public func load(showing itemID: MediaItem.ID?, near hint: Int = 0) async throws {
        try await pager.start()
        if let itemID, let index = try await pager.index(of: itemID, near: hint) {
            go(to: index)
        }
    }

    /// The next photo; `false` at the last.
    @discardableResult
    public func next() -> Bool {
        guard position + 1 < pager.count else { return false }
        go(to: position + 1)
        return true
    }

    /// The previous photo; `false` at the first.
    @discardableResult
    public func previous() -> Bool {
        guard position > 0 else { return false }
        go(to: position - 1)
        return true
    }

    public func startSlideshow() {
        isRunning = true
        isPaused = false
        // A clip's time starts when it ends.
        if current?.kind != .video {
            restartTime()
        }
    }

    public func stopSlideshow() {
        isRunning = false
        isPaused = false
        timer?.cancel()
    }

    /// Holds the slideshow, as Wholphin does while the details show.
    public func pause() {
        guard isRunning else { return }
        isPaused = true
        timer?.cancel()
    }

    public func resume() {
        guard isRunning else { return }
        isPaused = false
        restartTime()
    }

    /// The photo showing has loaded, or failed to: its time starts now.
    public func photoShown() {
        restartTime()
    }

    /// A clip started playing: the slideshow waits for its end.
    public func clipStarted() {
        timer?.cancel()
    }

    /// The clip showing played to its end.
    public func clipEnded() {
        restartTime()
    }

    /// Counts the time again from now, as Wholphin does after each press it handles.
    public func restartTime() {
        timer?.cancel()
        guard isActive else { return }
        let delay = delay
        timer = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.moveOn()
        }
    }

    /// The next photo, or the first after the last. Its time starts once it has loaded.
    private func moveOn() {
        guard isActive else { return }
        if !next() {
            go(to: 0)
        }
    }

    private func go(to index: Int) {
        position = index
        guard current == nil else { return }
        let pager = pager
        Task { [weak self] in
            do {
                _ = try await pager.load(at: index)
            } catch {
                // Nothing to wait for: on to the next one in time.
                self?.restartTime()
            }
        }
    }
}
