import AnemoneCore
import AnemoneJellyfin
import AVFoundation
import JellyfinAPI
import QuartzCore

/// Which engine plays an entry.
public enum EngineKind: Hashable, Sendable {
    case avPlayer
    case mpv
}

public extension PlayerBackend {
    /// Wholphin's rules (`PlaybackViewModel.createPlayer`): AVPlayer or MPV for everything, or
    /// with "Prefer MPV", AVPlayer for HDR and Dolby Vision, which MPV can't show as well, and
    /// for 4K that MPV would have to decode in software.
    func engine(for video: ItemVideo?, hardwareDecoding: Bool) -> EngineKind {
        switch self {
        case .avPlayer:
            .avPlayer
        case .mpv:
            .mpv
        case .preferMPV:
            video?.isHDR == true || (video?.is4K == true && !hardwareDecoding) ? .avPlayer : .mpv
        }
    }
}

/// An engine that settles how to play each entry before the controller asks the server for
/// it, since what the server is told the player can play depends on it.
@MainActor
public protocol PerEntryEngine: PlayerEngine {
    func prepare(for entry: PlaybackQueue.Entry) async
}

/// Gives the MPV engine playing, when one is, to what only MPV can do, such as subtitle delay.
@MainActor
public protocol MPVEngineProviding: AnyObject {
    var mpvEngine: MPVPlayerEngine? { get }
}

extension MPVPlayerEngine: MPVEngineProviding {
    public var mpvEngine: MPVPlayerEngine? {
        self
    }
}

public extension PlayerEngine {
    /// The MPV engine playing, if any.
    var mpv: MPVPlayerEngine? {
        (self as? any MPVEngineProviding)?.mpvEngine
    }
}

public enum PlayerChoice {
    /// The engine for a new player, from Settings: AVPlayer or MPV, or for "Prefer MPV" one
    /// that picks per entry, as Wholphin picks its player per item.
    @MainActor
    public static func engine(for session: JellyfinSession) -> any PlayerEngine {
        engine(for: Preferences.playerBackend.value(), session: session)
    }

    @MainActor
    static func engine(for backend: PlayerBackend, session: JellyfinSession) -> any PlayerEngine {
        #if os(tvOS) || os(iOS)
            switch backend {
            case .avPlayer:
                return AVPlayerEngine()
            case .mpv:
                return MPVPlayerEngine.withUserSettings()
            case .preferMPV:
                let hardwareDecoding = Preferences.mpvHardwareDecoding.value()
                return SwitchingEngine(
                    choose: { entry in
                        let video = try? await session.itemVideo(of: entry.itemID)
                        return backend.engine(for: video, hardwareDecoding: hardwareDecoding)
                    },
                    makeMPV: MPVPlayerEngine.withUserSettings,
                )
            }
        #else
            return AVPlayerEngine()
        #endif
    }
}

#if os(tvOS) || os(iOS)
    extension MPVPlayerEngine {
        /// An engine set up from Settings, with the user's subtitle style.
        static func withUserSettings() -> MPVPlayerEngine {
            let engine = MPVPlayerEngine()
            engine.setSubtitleStyles(.current)
            return engine
        }
    }
#endif

/// "Prefer MPV": plays each entry in MPV or AVPlayer as `choose` says, keeping one engine of
/// each kind, as Wholphin keeps its player until an item needs the other. Both draw into one
/// layer, so the player shows Anemone's overlay throughout, and whatever holds on to the
/// controller's engine (the overlay's seeker, features) follows the switch.
@MainActor
public final class SwitchingEngine: PerEntryEngine, MPVEngineProviding {
    public typealias Choose = @MainActor (PlaybackQueue.Entry) async -> EngineKind

    private let choose: Choose
    private let makeMPV: @MainActor () -> MPVPlayerEngine
    private let container = EngineLayer()
    private var avPlayer: AVPlayerEngine?
    private var mpvPlayer: MPVPlayerEngine?
    private var speed: Float = 1
    /// The engine playing; MPV until an entry says otherwise.
    public private(set) var kind = EngineKind.mpv
    private var isShown = false

    init(choose: @escaping Choose, makeMPV: @escaping @MainActor () -> MPVPlayerEngine) {
        self.choose = choose
        self.makeMPV = makeMPV
    }

    public func prepare(for entry: PlaybackQueue.Entry) async {
        let kind = await choose(entry)
        guard kind != self.kind || !isShown else { return }
        if isShown {
            active.stop()
        }
        self.kind = kind
        isShown = true
        active.rate = speed
        show(active)
    }

    public var mpvEngine: MPVPlayerEngine? {
        kind == .mpv ? mpvPlayer : nil
    }

    /// The engine playing, made when it's first needed.
    private var active: any PlayerEngine {
        switch kind {
        case .avPlayer:
            if let avPlayer {
                return avPlayer
            }
            let engine = AVPlayerEngine()
            avPlayer = engine
            return engine
        case .mpv:
            if let mpvPlayer {
                return mpvPlayer
            }
            let engine = makeMPV()
            mpvPlayer = engine
            return engine
        }
    }

    private func show(_ engine: any PlayerEngine) {
        switch engine.videoOutput {
        case let .avPlayer(player):
            let layer = AVPlayerLayer(player: player)
            layer.videoGravity = .resizeAspect
            container.show(layer)
        case let .layer(layer):
            container.show(layer)
        }
    }

    // MARK: - PlayerEngine

    public var deviceProfile: DeviceProfile {
        active.deviceProfile
    }

    public var videoOutput: PlayerVideoOutput {
        .layer(container)
    }

    public func load(_ url: URL, from position: Duration?, metadata: PlaybackMetadata) -> AsyncStream<PlayerEvent> {
        active.load(url, from: position, metadata: metadata)
    }

    public func play() {
        active.play()
    }

    public func pause() {
        active.pause()
    }

    public func stop() {
        active.stop()
    }

    public func seek(to position: Duration) async -> Bool {
        await active.seek(to: position)
    }

    public var currentTime: Duration {
        active.currentTime
    }

    public var duration: Duration? {
        active.duration
    }

    public var rate: Float {
        get { speed }
        set {
            speed = newValue
            active.rate = newValue
        }
    }

    public func tracks(_ kind: PlayerTrack.Kind) async -> [PlayerTrack] {
        await active.tracks(kind)
    }

    public func select(_ track: PlayerTrack?, _ kind: PlayerTrack.Kind) async {
        await active.select(track, kind)
    }
}

/// Holds the playing engine's video layer and keeps it the size of the player.
final class EngineLayer: CALayer {
    private var shown: CALayer?

    func show(_ layer: CALayer) {
        guard layer !== shown else { return }
        shown?.removeFromSuperlayer()
        shown = layer
        layer.frame = bounds
        addSublayer(layer)
    }

    override func layoutSublayers() {
        super.layoutSublayers()
        shown?.frame = bounds
    }
}

/// The engine's profile at the moment a stream is asked for, since "Prefer MPV" changes
/// engines between entries.
@MainActor
final class DeviceProfileSource {
    private let engine: any PlayerEngine

    init(_ engine: any PlayerEngine) {
        self.engine = engine
    }

    var current: DeviceProfile {
        engine.deviceProfile
    }
}
