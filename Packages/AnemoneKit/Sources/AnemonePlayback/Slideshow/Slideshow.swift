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
///
/// A running slideshow never gets stuck: a photo or clip that fails shows its message for the
/// set time, as in Wholphin, and is passed over after that; one that takes longer than
/// `loadTimeout` to load, or a clip that runs that long past its length, is moved on from.
@MainActor
@Observable
public final class Slideshow {
    /// Wholphin's limits for the time each photo shows.
    public static let durationRange = 1000 ... 30000

    /// Waits for a length of time before the slideshow moves on. Tests pass their own, so they
    /// don't depend on how busy the machine is.
    public typealias Sleep = @Sendable (Duration) async throws -> Void

    public let pager: SlideshowPager
    /// The photo showing, or about to once its page loads.
    public private(set) var position = 0
    /// Wholphin's slideshow mode: whether it moves on by itself.
    public private(set) var isRunning = false
    /// Held while the details show.
    public private(set) var isPaused = false
    @ObservationIgnored private let delay: Duration
    @ObservationIgnored private let loadTimeout: Duration
    @ObservationIgnored private let sleep: Sleep
    @ObservationIgnored private var timer: Task<Void, Never>?
    /// Photos and clips that couldn't be shown, which a running slideshow passes over.
    @ObservationIgnored private var failed: Set<MediaItem.ID> = []
    /// How long the clip showing is, once it's playing.
    @ObservationIgnored private var clipLength: Duration?
    /// The photo on screen, once it has loaded. Moving to it again, as a slideshow of one photo
    /// does, or back to it while the next is still loading behind it, changes nothing on screen,
    /// so no `photoShown()` comes; its time starts at once instead.
    @ObservationIgnored private var shownID: MediaItem.ID?

    /// - Parameters:
    ///   - loadTimeout: how long a running slideshow waits for a photo or clip to load before
    ///     moving on anyway.
    ///   - sleep: waits for each photo's time, `Task.sleep` unless a test passes its own.
    public init(
        pager: SlideshowPager,
        delay: Duration,
        loadTimeout: Duration = .seconds(15),
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
    ) {
        self.pager = pager
        self.delay = delay
        self.loadTimeout = loadTimeout
        self.sleep = sleep
    }

    /// How long each photo shows, from the user's setting within Wholphin's limits.
    public static func delay(in defaults: UserDefaults = .standard) -> Duration {
        // Also given as a launch argument (`-slideshowDuration 2000`), which arrives as text.
        let milliseconds = Preferences.slideshowDuration.value(in: defaults)
        return .milliseconds(
            durationRange.contains(milliseconds) ? milliseconds : Preferences.slideshowDuration.defaultValue,
        )
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
        if current?.kind == .video {
            wait((clipLength ?? .zero) + loadTimeout)
        } else {
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

    /// The photo showing has loaded: its time starts now.
    public func photoShown() {
        shownID = current?.id
        restartTime()
    }

    /// The photo or clip with this ID couldn't be loaded or played. Showing, its message stays
    /// for its time, as Wholphin's does; after that a running slideshow passes over it.
    public func itemFailed(_ itemID: MediaItem.ID) {
        failed.insert(itemID)
        if current?.id == itemID {
            // Its message shows in place of the last photo.
            shownID = nil
            restartTime()
        }
    }

    /// A clip is about to play: the slideshow waits for it to start.
    public func clipStarted() {
        wait(loadTimeout)
    }

    /// The clip showing started playing, and is this long when known: the slideshow waits for
    /// its end, but not for good if it stalls on the way.
    public func clipPlaying(length: Duration?) {
        clipLength = length
        wait((length ?? .zero) + loadTimeout)
    }

    /// The clip showing played to its end.
    public func clipEnded() {
        restartTime()
    }

    /// Counts the time again from now, as Wholphin does after each press it handles.
    public func restartTime() {
        wait(delay)
    }

    /// Moves on after `length`, while running.
    private func wait(_ length: Duration) {
        timer?.cancel()
        guard isActive else { return }
        timer = Task { [weak self, sleep] in
            try? await sleep(length)
            guard !Task.isCancelled else { return }
            self?.moveOn()
        }
    }

    /// The next photo that hasn't failed, or the first after the last; when they all have, the
    /// next anyway. Its time starts once it has loaded, unless it doesn't in time, or at once
    /// when it's the photo already on screen.
    private func moveOn() {
        let count = pager.count
        guard isActive, count > 0 else { return }
        let following = (1 ... count).map { (position + $0) % count }
        let index = following.first { candidate in
            pager.item(at: candidate).map { !failed.contains($0.id) } ?? true
        } ?? following[0]
        go(to: index)
        guard let current else {
            wait(loadTimeout)
            return
        }
        if current.id == shownID {
            restartTime()
        } else if !failed.contains(current.id) {
            wait(loadTimeout)
        }
    }

    private func go(to index: Int) {
        if index != position {
            clipLength = nil
        }
        position = index
        if current?.kind == .video {
            // A clip plays in place of the photo view, which loads its photo afresh after it.
            shownID = nil
        }
        guard let current else {
            let pager = pager
            Task { [weak self] in
                do {
                    _ = try await pager.load(at: index)
                } catch {
                    // Nothing to wait for: on to the next one in time.
                    self?.restartTime()
                }
            }
            return
        }
        // It won't load this time either: its message shows for its time.
        if failed.contains(current.id) {
            restartTime()
        }
    }
}
