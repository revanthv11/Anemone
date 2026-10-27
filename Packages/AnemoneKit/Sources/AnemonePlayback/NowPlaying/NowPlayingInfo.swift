import Foundation
import MediaPlayer

/// What Now Playing shows about the entry playing: the info panel on the TV and Control Center,
/// and the Remote app on a phone. Shaped after Swiftfin's `NowPlayableStaticMetadata` and
/// `NowPlayableDynamicMetadata`, filled from what Wholphin's `toMediaMetadata` gives Android's
/// media session.
public struct NowPlayingInfo: Equatable, Sendable {
    public var metadata: PlaybackMetadata
    /// The artwork's image data, once it has loaded.
    public var artwork: Data?
    public var position: Duration
    /// `nil` until the engine knows it.
    public var duration: Duration?
    public var isPlaying: Bool
    /// The speed while playing, 1 being normal.
    public var rate: Float
    /// The entry's place in the queue, counting from 0, and the queue's length.
    public var queueIndex: Int
    public var queueCount: Int

    public init(
        metadata: PlaybackMetadata,
        artwork: Data? = nil,
        position: Duration = .zero,
        duration: Duration? = nil,
        isPlaying: Bool = false,
        rate: Float = 1,
        queueIndex: Int = 0,
        queueCount: Int = 1,
    ) {
        self.metadata = metadata
        self.artwork = artwork
        self.position = position
        self.duration = duration
        self.isPlaying = isPlaying
        self.rate = rate
        self.queueIndex = queueIndex
        self.queueCount = queueCount
    }

    /// For `MPNowPlayingInfoCenter`, without the artwork, which needs a platform image. The rate
    /// is 0 while paused, so the system stops the clock; while playing, it moves the position on
    /// by itself between updates.
    var properties: [String: Any] {
        var properties: [String: Any] = [
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
            MPMediaItemPropertyTitle: metadata.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position / .seconds(1),
            MPNowPlayingInfoPropertyPlaybackRate: Double(isPlaying ? rate : 0),
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(rate),
            MPNowPlayingInfoPropertyPlaybackQueueIndex: queueIndex,
            MPNowPlayingInfoPropertyPlaybackQueueCount: queueCount,
        ]
        // The episode, under the series' title, as the system player's info panel shows it.
        if let subtitle = metadata.subtitle {
            properties[MPMediaItemPropertyArtist] = subtitle
        }
        if let duration, duration > .zero {
            properties[MPMediaItemPropertyPlaybackDuration] = duration / .seconds(1)
        }
        return properties
    }
}
