import Foundation
import MediaPlayer

/// What Now Playing shows about the entry playing: the info panel on the TV and Control Center,
/// and the Remote app on a phone. Shaped after Swiftfin's `NowPlayableStaticMetadata` and
/// `NowPlayableDynamicMetadata`, filled from what Wholphin's `toMediaMetadata` gives Android's
/// media session.
public struct NowPlayingInfo: Equatable, Sendable {
    public var metadata: PlaybackMetadata
    /// The artwork, once it has loaded.
    public var artwork: NowPlayingArtwork?
    public var position: Duration
    /// `nil` until the engine knows it.
    public var duration: Duration?
    public var isPlaying: Bool
    /// The speed while playing, 1 being normal.
    public var rate: Float
    /// The entry's place in the queue, counting from 0, and the queue's length.
    public var queueIndex: Int
    public var queueCount: Int
    /// A song, which the system shows as music, with its album.
    public var isMusic: Bool
    public var album: String?

    public init(
        metadata: PlaybackMetadata,
        artwork: NowPlayingArtwork? = nil,
        position: Duration = .zero,
        duration: Duration? = nil,
        isPlaying: Bool = false,
        rate: Float = 1,
        queueIndex: Int = 0,
        queueCount: Int = 1,
        isMusic: Bool = false,
        album: String? = nil,
    ) {
        self.metadata = metadata
        self.artwork = artwork
        self.position = position
        self.duration = duration
        self.isPlaying = isPlaying
        self.rate = rate
        self.queueIndex = queueIndex
        self.queueCount = queueCount
        self.isMusic = isMusic
        self.album = album
    }

    /// For `MPNowPlayingInfoCenter`, without the artwork, which needs a platform image.
    var properties: [String: Any] {
        var properties = entryProperties
        setTiming(in: &properties)
        return properties
    }

    /// What stays the same while the entry plays at its place in the queue.
    var entryProperties: [String: Any] {
        var properties: [String: Any] = [
            MPNowPlayingInfoPropertyMediaType: (isMusic ? MPNowPlayingInfoMediaType.audio : .video).rawValue,
            MPMediaItemPropertyTitle: metadata.title,
            MPNowPlayingInfoPropertyPlaybackQueueIndex: queueIndex,
            MPNowPlayingInfoPropertyPlaybackQueueCount: queueCount,
        ]
        // The episode, under the series' title, as the system player's info panel shows it; for a
        // song, its artists.
        if let subtitle = metadata.subtitle {
            properties[MPMediaItemPropertyArtist] = subtitle
        }
        if let album {
            properties[MPMediaItemPropertyAlbumTitle] = album
        }
        return properties
    }

    /// Whether `other` shows the same entry, artwork and queue place, so only the timing changed.
    func showsSameEntry(as other: Self) -> Bool {
        metadata == other.metadata && artwork == other.artwork
            && queueIndex == other.queueIndex && queueCount == other.queueCount
            && isMusic == other.isMusic && album == other.album
    }

    /// Updates what moves while the entry plays. The rate is 0 while paused, so the system stops
    /// the clock; while playing, it moves the position on by itself between updates.
    func setTiming(in properties: inout [String: Any]) {
        properties[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position / .seconds(1)
        properties[MPNowPlayingInfoPropertyPlaybackRate] = Double(isPlaying ? rate : 0)
        properties[MPNowPlayingInfoPropertyDefaultPlaybackRate] = Double(rate)
        if let duration, duration > .zero {
            properties[MPMediaItemPropertyPlaybackDuration] = duration / .seconds(1)
        } else {
            properties.removeValue(forKey: MPMediaItemPropertyPlaybackDuration)
        }
    }
}

/// Artwork Now Playing has loaded: the image, and the URL it came from. Two are the same when
/// they came from the same URL, so the comparisons of what's shown, once a second, never compare
/// the images themselves.
public struct NowPlayingArtwork: Equatable, Sendable {
    public let url: URL
    public let data: Data

    public init(url: URL, data: Data) {
        self.url = url
        self.data = data
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.url == rhs.url
    }
}
