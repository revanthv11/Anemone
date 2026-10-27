import AVFoundation
import JellyfinAPI
import QuartzCore

/// What plays the video: AVPlayer today, and MPV in Phase 4. `PlaybackController` drives an
/// engine and never touches the player behind it, so a second engine only has to conform.
/// Shaped after Swiftfin's `MediaPlayer`, which keeps its AVPlayer and MPV players apart the
/// same way.
@MainActor
public protocol PlayerEngine: AnyObject {
    /// What the server is told this engine can play.
    var deviceProfile: DeviceProfile { get }
    /// Where the video appears, for the player UI to host.
    var videoOutput: PlayerVideoOutput { get }

    /// Starts loading `url` in place of whatever was loaded, ready to play from `position` (the
    /// beginning when `nil`), and returns what happens to it. The events end when something else
    /// loads or the engine stops. Nothing plays until `play()`.
    func load(_ url: URL, from position: Duration?, metadata: PlaybackMetadata) -> AsyncStream<PlayerEvent>
    func play()
    func pause()
    /// Unloads what's playing, ending its events.
    func stop()
    /// Jumps exactly to `position`, returning whether it got there: a newer seek can replace it.
    func seek(to position: Duration) async -> Bool

    var currentTime: Duration { get }
    /// `nil` until known, and for live streams.
    var duration: Duration? { get }
    /// The playback speed, 1 being normal, kept across pauses.
    var rate: Float { get set }

    /// The loaded stream's audio or subtitle tracks, in the engine's order.
    func tracks(_ kind: PlayerTrack.Kind) async -> [PlayerTrack]
    /// Switches to `track`, or turns subtitles off when `nil`.
    func select(_ track: PlayerTrack?, _ kind: PlayerTrack.Kind) async
}

/// What happens to a loaded stream.
public enum PlayerEvent: Sendable {
    /// Loaded and at its start position, waiting for `play()`.
    case ready
    /// Playing, paused, or waiting for data. The first one is the status at load.
    case status(PlayerStatus)
    /// Played to the end.
    case ended
    /// Couldn't load, couldn't reach the start position, or stopped partway.
    case failed(any Error)
}

public enum PlayerStatus: Sendable {
    case paused
    /// Asked to play, but waiting for data.
    case waiting
    case playing
}

/// An audio or subtitle track inside the loaded stream.
public struct PlayerTrack: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        case audio
        case subtitle
    }

    /// The engine's own reference: an index into AVFoundation's options, or MPV's track ID.
    public let id: Int
    public let kind: Kind
    public let title: String
    /// A BCP 47 tag such as `en` or `pt-BR`, when the stream says.
    public let language: String?
    public let isSelected: Bool
    /// The codec's name, such as `subrip` or `hdmv_pgs_subtitle`, when the engine says (MPV).
    public let codec: String?
    /// Whether it's a file added beside the stream rather than inside it, when the engine says
    /// (MPV, for the subtitle files it's given).
    public let isExternal: Bool?

    public init(
        id: Int,
        kind: Kind,
        title: String,
        language: String?,
        isSelected: Bool,
        codec: String? = nil,
        isExternal: Bool? = nil,
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.language = language
        self.isSelected = isSelected
        self.codec = codec
        self.isExternal = isExternal
    }
}

/// How the player UI shows an engine's video.
public enum PlayerVideoOutput {
    /// An AVPlayer, for `AVPlayerViewController` or an `AVPlayerLayer`.
    case avPlayer(AVPlayer)
    /// A layer the engine draws into itself, such as MPV's Metal layer.
    case layer(CALayer)
}
