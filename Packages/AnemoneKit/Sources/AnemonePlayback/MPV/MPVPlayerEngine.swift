import Foundation
import JellyfinAPI
import os
import QuartzCore
#if os(tvOS) || os(iOS)
    import UIKit
#endif

/// The MPV engine: libmpv (through MPVKit) direct-plays what AVPlayer can't, such as MKV, DTS,
/// TrueHD and ASS or PGS subtitles, and draws the video and subtitles into a Metal layer of its
/// own, so it always plays under Anemone's overlay. The counterpart of Wholphin's `MpvPlayer`
/// (wholphin-mpv) and Swiftfin's `MPVMediaPlayer`.
@MainActor
public final class MPVPlayerEngine: PlayerEngine {
    public let deviceProfile: DeviceProfile
    public let videoOutput: PlayerVideoOutput
    /// `nil` when libmpv couldn't start; every load then fails.
    private let client: (any MPVClient)?
    private var listener: Task<Void, Never>?
    /// The stream loading or loaded, until another replaces it or the engine stops.
    private var current: Load?
    /// Seeks waiting for libmpv to land, newest last. A newer seek replaces older ones.
    private var seeks: [(id: Int, done: CheckedContinuation<Bool, Never>)] = []
    private var seekCount = 0
    private var lastTime = Duration.zero
    private var speed: Float = 1
    /// What libmpv last said, which together decide the status.
    private var isPaused = true
    private var isBuffering = false
    private var isSeeking = false
    private var reportedStatus: PlayerStatus?
    /// What the subtitles look like, with a second look for HDR video if the user set one.
    private var subtitleStyles: SubtitleStyles?
    private var isHDR = false

    /// A stream being played: its events, where it starts, and how far it's got.
    private struct Load {
        let events: AsyncStream<PlayerEvent>.Continuation
        let start: Duration?
        /// libmpv started on this file; anything it says about the file before belongs to the
        /// one this replaced.
        var hasStarted = false
        var isReady = false
        var hasEnded = false
    }

    #if os(tvOS) || os(iOS)
        /// An engine with libmpv set up from the user's settings.
        public convenience init(maxBitrate: Int = AVPlayerProfile.defaultMaxBitrate) {
            let layer = MPVMetalLayer()
            layer.contentsScale = UITraitCollection.current.displayScale
            layer.backgroundColor = UIColor.black.cgColor
            self.init(
                client: LibMPVClient(layer: layer, options: MPVOptions.current.libmpvOptions),
                layer: layer,
                profile: MPVProfile.deviceProfile(maxBitrate: maxBitrate),
            )
        }
    #endif

    init(client: (any MPVClient)?, layer: CALayer, profile: DeviceProfile) {
        self.client = client
        videoOutput = .layer(layer)
        deviceProfile = profile
        listen()
    }

    isolated deinit {
        endLoad()
        listener?.cancel()
        client?.destroy()
    }

    public func load(_ url: URL, from position: Duration?, metadata: PlaybackMetadata) -> AsyncStream<PlayerEvent> {
        endLoad()
        let (stream, events) = AsyncStream.makeStream(of: PlayerEvent.self)
        guard let client else {
            events.yield(.failed(PlayerError.streamFailed(underlying: MPVError.unavailable)))
            events.finish()
            return stream
        }
        let start = position.flatMap { $0 > .zero ? $0 : nil }
        current = Load(events: events, start: start)
        lastTime = start ?? .zero
        reportedStatus = nil
        isHDR = false
        events.yield(.status(.paused))
        // Nothing plays until `play()`, as with AVPlayer.
        client.set("pause", true)
        var options = ["force-media-title=\(Self.escaped(metadata.title))"]
        if let start {
            options.append("start=\(Self.seconds(start))")
        }
        // The index argument (-1) only matters when inserting; options come after it.
        client.command(["loadfile", url.absoluteString, "replace", "-1", options.joined(separator: ",")])
        return stream
    }

    public func play() {
        client?.set("pause", false)
    }

    public func pause() {
        client?.set("pause", true)
    }

    public func stop() {
        endLoad()
        client?.command(["stop"])
    }

    /// Exact, like AVPlayer's, rather than to the keyframe before it. libmpv says it has landed
    /// with a playback restart; a newer seek replaces this one.
    public func seek(to position: Duration) async -> Bool {
        guard let client, current?.isReady == true else { return false }
        seekCount += 1
        let id = seekCount
        lastTime = position
        client.command(["seek", Self.seconds(position), "absolute+exact"])
        return await withCheckedContinuation { done in
            seeks.append((id, done))
        }
    }

    public var currentTime: Duration {
        if let seconds = client?.double("time-pos"), seconds.isFinite {
            lastTime = .seconds(seconds)
        }
        return lastTime
    }

    public var duration: Duration? {
        guard let seconds = client?.double("duration"), seconds.isFinite, seconds > 0 else { return nil }
        return .seconds(seconds)
    }

    /// libmpv keeps its speed across files and pauses.
    public var rate: Float {
        get { speed }
        set {
            speed = newValue
            client?.set("speed", Double(newValue))
        }
    }

    /// The file's own tracks, in libmpv's order, which is the file's.
    public func tracks(_ kind: PlayerTrack.Kind) async -> [PlayerTrack] {
        guard let client else { return [] }
        return MPVTrackList.tracks(kind, from: client)
    }

    public func select(_ track: PlayerTrack?, _ kind: PlayerTrack.Kind) async {
        client?.set(kind == .audio ? "aid" : "sid", track.map { String($0.id) } ?? "no")
    }

    // MARK: - MPV only

    /// How far subtitles are shifted: later when positive. Wholphin's subtitle delay.
    public var subtitleDelay: Duration = .zero {
        didSet {
            client?.set("sub-delay", subtitleDelay / .seconds(1))
        }
    }

    /// Styles text subtitles: SRT and the like, and ASS when the file's styles are overridden.
    /// HDR video gets `hdr` when the user set one, since full-white text is glaring in HDR.
    public func setSubtitleStyles(_ styles: SubtitleStyles) {
        subtitleStyles = styles
        applySubtitleStyle()
    }

    /// Adds subtitles from outside the file, such as ones just downloaded, and shows them.
    public func addSubtitles(from url: URL, title: String, language: String?) {
        var arguments = ["sub-add", url.absoluteString, "select", title]
        if let language {
            arguments.append(language)
        }
        client?.command(arguments)
    }

    // MARK: - libmpv's events

    private func listen() {
        guard let events = client?.events else { return }
        listener = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                handle(event)
            }
        }
    }

    func handle(_ event: MPVEvent) {
        switch event {
        case .fileLoaded:
            current?.hasStarted = true
        case .playbackRestart:
            restarted()
        case let .endFile(reason):
            ended(reason)
        case let .property(name, value):
            changed(name, to: value)
        case .shutdown:
            endLoad()
        }
    }

    private func restarted() {
        guard var load = current, load.hasStarted else { return }
        guard load.isReady else {
            load.isReady = true
            current = load
            logDecoding()
            load.events.yield(.ready)
            reportStatus()
            return
        }
        // A seek landed: the newest one got there, older ones were replaced.
        finishSeeks { $0 == seekCount }
    }

    private func ended(_ reason: MPVEndReason) {
        guard let load = current, load.hasStarted else { return }
        switch reason {
        case let .failed(message):
            load.events.yield(.failed(PlayerError.streamFailed(underlying: MPVError(reason: message))))
            endLoad()
        case .endOfFile:
            reachedEnd()
        case .stopped:
            break
        }
    }

    private func changed(_ name: String, to value: MPVValue) {
        switch name {
        case "pause":
            isPaused = value.flag ?? isPaused
        case "paused-for-cache":
            isBuffering = value.flag ?? false
        case "seeking":
            isSeeking = value.flag ?? false
        case "eof-reached":
            if value.flag == true {
                reachedEnd()
            }
            return
        case "video-params/gamma":
            // PQ is HDR10 and Dolby Vision's, HLG broadcast HDR's.
            if case let .string(gamma) = value {
                isHDR = ["pq", "hlg"].contains(gamma)
                applySubtitleStyle()
            }
            return
        default:
            return
        }
        reportStatus()
    }

    /// With `keep-open`, the last frame stays up at the end, as with AVPlayer, for Up Next.
    private func reachedEnd() {
        guard var load = current, load.isReady, !load.hasEnded else { return }
        load.hasEnded = true
        current = load
        finishSeeks { _ in true }
        load.events.yield(.ended)
    }

    private func reportStatus() {
        guard let load = current, load.isReady else { return }
        let status: PlayerStatus = if isPaused {
            .paused
        } else if isBuffering || isSeeking {
            .waiting
        } else {
            .playing
        }
        guard status != reportedStatus else { return }
        reportedStatus = status
        load.events.yield(.status(status))
    }

    private func applySubtitleStyle() {
        guard let client, let subtitleStyles else { return }
        for (name, value) in subtitleStyles.style(forHDR: isHDR).mpvProperties {
            client.set(name, value)
        }
    }

    /// In debug builds, what libmpv decodes, for live checks in the console.
    private func logDecoding() {
        #if DEBUG
            guard let client else { return }
            let names = ["video-codec", "hwdec-current", "audio-codec-name", "audio-params/hr-channels", "sid", "vo"]
            let values = names.map { "\($0)=\(client.string($0) ?? "-")" }.joined(separator: " ")
            Logger.mpv.info("playing: \(values, privacy: .public)")
        #endif
    }

    /// Ends the current stream's events; seeks waiting for it didn't get there.
    private func endLoad() {
        finishSeeks { _ in false }
        current?.events.finish()
        current = nil
    }

    private func finishSeeks(_ landed: (Int) -> Bool) {
        let waiting = seeks
        seeks = []
        for seek in waiting {
            seek.done.resume(returning: landed(seek.id))
        }
    }

    /// Seconds as libmpv reads them.
    static func seconds(_ duration: Duration) -> String {
        String(format: "%.3f", duration / .seconds(1))
    }

    /// A value for loadfile's option list, which commas and quotes would break: libmpv's
    /// `%n%` prefix gives the value's length, so anything can follow.
    static func escaped(_ value: String) -> String {
        "%\(value.utf8.count)%\(value)"
    }
}

/// The layer libmpv draws in. MoltenVK briefly sets the drawable size to 1×1 to finish a
/// presentation, which can leave the video flickering or stuck at that size, so such sizes are
/// ignored. From MPVKit's demo (`MetalLayer`, LGPL-3.0), after mpv-player/mpv#13651.
final class MPVMetalLayer: CAMetalLayer {
    override var drawableSize: CGSize {
        get { super.drawableSize }
        set {
            if Int(newValue.width) > 1, Int(newValue.height) > 1 {
                super.drawableSize = newValue
            }
        }
    }
}
