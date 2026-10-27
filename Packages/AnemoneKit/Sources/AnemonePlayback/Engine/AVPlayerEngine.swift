import AVFoundation
import Combine
import JellyfinAPI
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

/// The AVPlayer engine, which the system player (`AVPlayerViewController`) shows.
@MainActor
public final class AVPlayerEngine: PlayerEngine {
    public let player = AVPlayer()
    /// Following the loaded item, cancelled when it's replaced or the engine stops.
    private var watchers: [Task<Void, Never>] = []
    private var events: AsyncStream<PlayerEvent>.Continuation?

    public init() {}

    public var deviceProfile: DeviceProfile {
        AVPlayerProfile.current
    }

    public var videoOutput: PlayerVideoOutput {
        .avPlayer(player)
    }

    public func load(_ url: URL, from position: Duration?, metadata: PlaybackMetadata) -> AsyncStream<PlayerEvent> {
        stopWatching()
        let item = AVPlayerItem(url: url)
        #if os(tvOS) || os(iOS)
            item.externalMetadata = metadata.avMetadata
        #endif
        // AVPlayer keeps its rate across items, so after a stream that failed while playing, the
        // next would start from 0 before it's ready and at its position.
        player.pause()
        player.replaceCurrentItem(with: item)
        let (stream, events) = AsyncStream.makeStream(of: PlayerEvent.self)
        self.events = events
        watch(item, startingAt: position.flatMap { $0 > .zero ? $0 : nil }, events: events)
        return stream
    }

    public func play() {
        player.play()
    }

    public func pause() {
        player.pause()
    }

    public func stop() {
        stopWatching()
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    /// Exact, like Wholphin's resume, rather than the keyframe before it.
    public func seek(to position: Duration) async -> Bool {
        await player.seek(
            to: CMTime(seconds: position / .seconds(1), preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero,
        )
    }

    public var currentTime: Duration {
        player.currentTime().duration ?? .zero
    }

    public var duration: Duration? {
        player.currentItem?.duration.duration
    }

    /// AVPlayer's default rate, which `play()` uses; set while playing, it applies at once.
    public var rate: Float {
        get { player.defaultRate }
        set {
            player.defaultRate = newValue
            if player.rate != 0 {
                player.rate = newValue
            }
        }
    }

    /// The tracks AVFoundation offers through media selection: those in the file when playing it
    /// directly, and in the HLS playlist otherwise.
    public func tracks(_ kind: PlayerTrack.Kind) async -> [PlayerTrack] {
        guard let item = player.currentItem, let group = await Self.group(kind, in: item) else { return [] }
        let selected = item.currentMediaSelection.selectedMediaOption(in: group)
        return group.options.enumerated().map { index, option in
            PlayerTrack(
                id: index,
                kind: kind,
                title: option.displayName,
                language: option.extendedLanguageTag,
                isSelected: option == selected,
            )
        }
    }

    public func select(_ track: PlayerTrack?, _ kind: PlayerTrack.Kind) async {
        guard let item = player.currentItem, let group = await Self.group(kind, in: item) else { return }
        let option = track.flatMap { group.options.indices.contains($0.id) ? group.options[$0.id] : nil }
        item.select(option, in: group)
    }

    private static func group(_ kind: PlayerTrack.Kind, in item: AVPlayerItem) async -> AVMediaSelectionGroup? {
        try? await item.asset.loadMediaSelectionGroup(for: kind == .audio ? .audible : .legible)
    }

    private func stopWatching() {
        watchers.forEach { $0.cancel() }
        watchers = []
        events?.finish()
        events = nil
    }
}

/// Following the player.
private extension AVPlayerEngine {
    func watch(_ item: AVPlayerItem, startingAt position: Duration?, events: AsyncStream<PlayerEvent>.Continuation) {
        watchers = [
            Task { [weak self] in
                for await status in changes(of: item, \.status) {
                    switch status {
                    case .readyToPlay:
                        await self?.ready(startingAt: position, events: events)
                        return
                    case .failed:
                        events.yield(.failed(PlayerError.streamFailed(underlying: item.error)))
                        return
                    default:
                        continue
                    }
                }
            },
            Task {
                let failures = NotificationCenter.default.notifications(
                    named: AVPlayerItem.failedToPlayToEndTimeNotification,
                    object: item,
                )
                for await _ in failures {
                    events.yield(.failed(PlayerError.streamFailed(underlying: item.error)))
                    return
                }
            },
            Task {
                let ends = NotificationCenter.default.notifications(
                    named: AVPlayerItem.didPlayToEndTimeNotification,
                    object: item,
                )
                for await _ in ends {
                    events.yield(.ended)
                    return
                }
            },
            Task { [player] in
                for await status in changes(of: player, \.timeControlStatus) {
                    events.yield(.status(PlayerStatus(status)))
                }
            },
        ]
    }

    func ready(startingAt position: Duration?, events: AsyncStream<PlayerEvent>.Continuation) async {
        // Once the item is ready, as Swiftfin does. Playing from the start after a failed seek
        // would lose the user's place once the first progress report went out; a seek replaced
        // by the user's own scrubbing is fine.
        if let position, await !seek(to: position), currentTime < .seconds(1) {
            events.yield(.failed(PlayerError.resumeFailed))
            return
        }
        events.yield(.ready)
    }
}

private extension PlayerStatus {
    init(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .playing: self = .playing
        case .waitingToPlayAtSpecifiedRate: self = .waiting
        default: self = .paused
        }
    }
}

#if os(tvOS) || os(iOS)
    private extension PlaybackMetadata {
        /// For AVKit's title view and info panel, which read the title and subtitle by these
        /// identifiers.
        var avMetadata: [AVMetadataItem] {
            var metadata = [Self.item(.commonIdentifierTitle, title)]
            if let subtitle {
                metadata.append(Self.item(.iTunesMetadataTrackSubTitle, subtitle))
            }
            if let overview {
                metadata.append(Self.item(.commonIdentifierDescription, overview))
            }
            return metadata
        }

        static func item(_ identifier: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
            let item = AVMutableMetadataItem()
            item.identifier = identifier
            item.value = value as NSString
            item.extendedLanguageTag = "und"
            return item
        }
    }
#endif

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
