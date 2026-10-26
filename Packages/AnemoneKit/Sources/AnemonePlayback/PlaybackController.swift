import AnemoneJellyfin
import AVFoundation
import Combine
import JellyfinAPI
import Observation
#if os(tvOS) || os(iOS)
    // The player's title and description on `AVPlayerItem`.
    import AVKit
#endif

/// Why AVPlayer couldn't play what the server sent.
public enum PlayerError: Error {
    /// The stream failed to load or stopped partway; `underlying` is AVFoundation's reason.
    case streamFailed(underlying: (any Error)?)
    /// Playback couldn't jump to the resume position.
    case resumeFailed
}

/// Plays one item with AVPlayer: asks the server for a stream, starts at the requested position,
/// switches to a transcode if the file won't play, and reports progress. Ported from the parts of
/// Wholphin's `PlaybackViewModel` that play a single item.
@MainActor
@Observable
public final class PlaybackController: Identifiable {
    public enum State {
        case loading
        case playing
        /// Played to the end.
        case ended
        case failed(any Error)
    }

    /// How often progress is saved while playing, as in Wholphin.
    static let progressInterval = Duration.seconds(5)

    public let itemID: MediaItem.ID
    public let player = AVPlayer()
    public private(set) var state = State.loading

    public var hasEnded: Bool {
        if case .ended = state { true } else { false }
    }

    @ObservationIgnored private let session: JellyfinSession
    @ObservationIgnored private let startPosition: Duration?
    @ObservationIgnored private let metadata: [AVMetadataItem]
    @ObservationIgnored private let profile: DeviceProfile
    @ObservationIgnored private let reporter: PlaybackReporter
    /// What's loaded in the player.
    @ObservationIgnored private var stream: PlaybackStream?
    /// Tasks following the loaded stream, cancelled when it's replaced or playback stops.
    @ObservationIgnored private var watchers: [Task<Void, Never>] = []
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var isStopped = false

    /// - Parameters:
    ///   - startPosition: where to start; the beginning when `nil`.
    ///   - metadata: the title and description the player shows.
    public init(
        session: JellyfinSession,
        itemID: MediaItem.ID,
        startPosition: Duration? = nil,
        metadata: [AVMetadataItem] = [],
        profile: DeviceProfile = AVPlayerProfile.current,
    ) {
        self.session = session
        self.itemID = itemID
        self.startPosition = startPosition
        self.metadata = metadata
        self.profile = profile
        reporter = PlaybackReporter { report in
            switch report {
            case let .start(stream, progress):
                try await session.reportPlaybackStart(stream, at: progress)
            case let .progress(stream, progress):
                try await session.reportPlaybackProgress(stream, at: progress)
            case let .stop(stream, position):
                try await session.reportPlaybackStopped(stream, at: position)
            }
        }
    }

    /// Asks the server for a stream and starts playing it. Only the first call does anything, so
    /// a view that runs it again doesn't open a second play session.
    public func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        await load(allowsDirect: true, from: startPosition)
    }

    /// Stops playing and ends the play session, returning once the server has heard. Call when
    /// the player closes.
    public func stop() async {
        guard !isStopped else { return }
        isStopped = true
        let position = currentPosition
        stopWatching()
        player.pause()
        player.replaceCurrentItem(with: nil)
        await reporter.stop(at: position)
    }

    private func load(allowsDirect: Bool, from position: Duration?) async {
        guard !isStopped else { return }
        do {
            let stream = try await session.playbackStream(
                for: itemID,
                profile: profile,
                maxBitrate: AVPlayerProfile.defaultMaxBitrate,
                allowsDirect: allowsDirect,
                mediaSourceID: stream?.mediaSourceID,
            )
            guard !isStopped else { return }
            play(stream, from: position)
        } catch {
            guard !isStopped else { return }
            state = .failed(error)
        }
    }

    private func play(_ stream: PlaybackStream, from position: Duration?) {
        self.stream = stream
        let item = AVPlayerItem(url: stream.url)
        #if os(tvOS) || os(iOS)
            item.externalMetadata = metadata
        #endif
        player.replaceCurrentItem(with: item)
        watch(item, resumingAt: position.flatMap { $0 > .zero ? $0 : nil })
    }

    /// Wholphin's `onPlayerError`: a file that won't direct play or direct stream gets another
    /// try as a transcode, from where it stopped. A transcode that fails is an error.
    private func failed(_ error: any Error) {
        guard !isStopped, let stream else { return }
        // Called from a watcher, which this cancels; the retry runs on its own.
        stopWatching()
        guard stream.method != .transcode else {
            state = .failed(error)
            return
        }
        let position = currentPosition
        state = .loading
        Task {
            // The failed session ends before the transcode's starts.
            await reporter.stop(at: position)
            await load(allowsDirect: false, from: position > .zero ? position : startPosition)
        }
    }

    private func finished() async {
        stopWatching()
        state = .ended
        if let duration = player.currentItem?.duration.duration {
            await reporter.stop(at: duration)
        }
    }

    private var currentPosition: Duration {
        player.currentTime().duration ?? .zero
    }

    private var currentProgress: PlaybackProgress {
        PlaybackProgress(position: currentPosition, isPaused: player.timeControlStatus == .paused)
    }

    private func stopWatching() {
        watchers.forEach { $0.cancel() }
        watchers = []
    }
}

/// Following the player.
private extension PlaybackController {
    func watch(_ item: AVPlayerItem, resumingAt position: Duration?) {
        stopWatching()
        watchers = [
            Task { [weak self] in
                for await status in changes(of: item, \.status) {
                    switch status {
                    case .readyToPlay:
                        await self?.ready(resumingAt: position)
                        return
                    case .failed:
                        self?.failed(PlayerError.streamFailed(underlying: item.error))
                        return
                    default:
                        continue
                    }
                }
            },
            Task { [weak self] in
                let failures = NotificationCenter.default.notifications(
                    named: AVPlayerItem.failedToPlayToEndTimeNotification,
                    object: item,
                )
                for await _ in failures {
                    self?.failed(PlayerError.streamFailed(underlying: item.error))
                    return
                }
            },
            Task { [weak self] in
                let ends = NotificationCenter.default.notifications(
                    named: AVPlayerItem.didPlayToEndTimeNotification,
                    object: item,
                )
                for await _ in ends {
                    await self?.finished()
                    return
                }
            },
        ]
    }

    func ready(resumingAt position: Duration?) async {
        // Once the item is ready, as Swiftfin does. Playing from the start after a failed seek
        // would lose the user's place once the first progress report went out; a seek replaced
        // by the user's own scrubbing is fine.
        if let position, await !seek(to: position), currentPosition < .seconds(1) {
            failed(PlayerError.resumeFailed)
            return
        }
        guard !isStopped else { return }
        state = .playing
        player.play()
        watchers.append(Task { [weak self] in
            await self?.reportWhilePlaying()
        })
    }

    /// Exact, like Wholphin's resume, rather than the keyframe before it.
    func seek(to position: Duration) async -> Bool {
        await player.seek(
            to: CMTime(seconds: position / .seconds(1), preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero,
        )
    }

    /// Like Wholphin: the start report once playback is under way, then progress every few
    /// seconds and whenever it pauses or resumes.
    func reportWhilePlaying() async {
        let statuses = changes(of: player, \.timeControlStatus)
        for await status in statuses where status == .playing {
            break
        }
        guard !Task.isCancelled, let stream else { return }
        reporter.start(stream, at: currentProgress)
        watchers.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.progressInterval)
                self?.saveProgress()
            }
        })
        var wasPaused = false
        for await status in statuses where status != .waitingToPlayAtSpecifiedRate {
            let isPaused = status == .paused
            if isPaused != wasPaused {
                wasPaused = isPaused
                saveProgress()
            }
        }
    }

    /// Wholphin doesn't save a position at the very start.
    func saveProgress() {
        let progress = currentProgress
        if progress.position > .zero {
            reporter.progress(progress)
        }
    }
}

/// Every change to a property, starting with its current value. Combine's `values` alone drops
/// a change that comes before the loop asks for the next one, such as an item becoming ready.
private func changes<Root: NSObject, Value>(
    of object: Root,
    _ keyPath: KeyPath<Root, Value>,
) -> AsyncPublisher<Publishers.Buffer<NSObject.KeyValueObservingPublisher<Root, Value>>> {
    object.publisher(for: keyPath).buffer(size: 8, prefetch: .keepFull, whenFull: .dropOldest).values
}

private extension CMTime {
    /// `nil` for invalid or indefinite times, such as a live stream's duration.
    var duration: Duration? {
        guard isNumeric, seconds.isFinite else { return nil }
        return .seconds(seconds)
    }
}
