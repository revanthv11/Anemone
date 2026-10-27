import AnemoneJellyfin
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
    private var current: MPVLoad?
    /// The newest playlist entry libmpv has made, as far as the engine knows: the newest it has
    /// named, or one more for each load it took without naming the entry it made. libmpv makes
    /// one entry for each `loadfile`, numbered in order, so a load whose entry libmpv didn't say
    /// is the first entry to start after this.
    private var newestEntry: Int64 = 0
    private let seeks: MPVSeeks
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

    init(client: (any MPVClient)?, layer: CALayer, profile: DeviceProfile, seeks: MPVSeeks = MPVSeeks()) {
        self.client = client
        videoOutput = .layer(layer)
        deviceProfile = profile
        self.seeks = seeks
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
        // Nothing plays until `play()`, as with AVPlayer.
        client.set("pause", true)
        var options = ["force-media-title=\(Self.escaped(metadata.title))"]
        if let start {
            options.append("start=\(Self.seconds(start))")
        }
        // The index argument (-1) only matters when inserting; options come after it.
        let arguments = ["loadfile", url.absoluteString, "replace", "-1", options.joined(separator: ",")]
        guard case let .started(entry) = client.loadFile(arguments) else {
            events.yield(.failed(PlayerError.streamFailed(underlying: MPVError.refused)))
            events.finish()
            return stream
        }
        current = MPVLoad(events: events, url: url, entry: entry, newerThan: newestEntry)
        // Counting a load without a named entry too, so another after it doesn't take its entry.
        newestEntry = entry.map { max(newestEntry, $0) } ?? newestEntry + 1
        lastTime = start ?? .zero
        reportedStatus = nil
        isHDR = false
        events.yield(.status(.paused))
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
    /// with a playback restart; a newer seek replaces this one, and one libmpv refuses, as on a
    /// live stream, doesn't get there (see `MPVSeeks`).
    public func seek(to position: Duration) async -> Bool {
        guard let client, current?.isReady == true else { return false }
        let arguments = ["seek", Self.seconds(position), "absolute+exact"]
        let landed = await seeks.land { id in
            guard client.commandAsync(arguments, id: id) else { return false }
            lastTime = position
            return true
        }
        #if DEBUG
            Logger.mpv.info("seek to \(Self.seconds(position), privacy: .public): \(landed ? "landed" : "didn't land")")
        #endif
        return landed
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

    /// Adds subtitles from outside the file, such as ones just downloaded, listed among the
    /// tracks, and shows them unless `selecting` is off.
    public func addSubtitles(from url: URL, title: String, language: String?, selecting: Bool = true) {
        var arguments = ["sub-add", url.absoluteString, selecting ? "select" : "auto", title]
        if let language {
            arguments.append(language)
        }
        client?.command(arguments)
    }

    /// How long the server says the stream loaded from `url` runs, which tells its end from a
    /// cut-off better than libmpv's duration (see `isRealEnd`); nothing if another stream has
    /// replaced it.
    public func setRuntime(_ runtime: Duration?, forStreamFrom url: URL) {
        guard current?.url == url else { return }
        current?.runtime = runtime
    }

    /// Adds the subtitle files beside the stream loaded from `url` once libmpv has opened it,
    /// showing the server's default; nothing if another stream has replaced it. MPV's profile
    /// has the server deliver such files as External, so they aren't in the stream itself.
    public func addExternalSubtitles(_ subtitles: [ExternalSubtitle], toStreamFrom url: URL) {
        guard current?.url == url else { return }
        guard current?.isLoaded == true else {
            current?.pendingSubtitles += subtitles
            return
        }
        add(subtitles)
    }

    private func add(_ subtitles: [ExternalSubtitle]) {
        for subtitle in subtitles {
            addSubtitles(
                from: subtitle.url,
                title: subtitle.title,
                language: subtitle.language,
                selecting: subtitle.isDefault,
            )
        }
    }
}

// MARK: - libmpv's events

extension MPVPlayerEngine {
    private func listen() {
        guard let events = client?.events else { return }
        listener = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                handle(event)
            }
        }
    }

    /// Events about a file count only when they name the current stream's entry.
    func handle(_ event: MPVEvent) {
        switch event {
        case let .startFile(entry):
            newestEntry = max(newestEntry, entry)
            current?.started(entry)
        case let .fileLoaded(entry) where current?.owns(entry) == true:
            fileLoaded()
        case let .seek(entry) where current?.owns(entry) == true:
            seeks.started()
        case let .playbackRestart(entry) where current?.owns(entry) == true:
            restarted()
        case let .endFile(entry, reason) where current?.owns(entry) == true:
            ended(reason)
        case let .commandReply(id, succeeded):
            seeks.replied(id, succeeded: succeeded)
        case let .property(name, value):
            changed(name, to: value)
        case .shutdown:
            fail(MPVError.stopped)
        case .fileLoaded, .seek, .playbackRestart, .endFile:
            break
        }
    }

    private func fileLoaded() {
        current?.isLoaded = true
        let pending = current?.pendingSubtitles ?? []
        current?.pendingSubtitles = []
        add(pending)
    }

    private func restarted() {
        guard var load = current else { return }
        guard load.isReady else {
            load.isReady = true
            current = load
            logDecoding()
            load.events.yield(.ready)
            reportStatus()
            return
        }
        seeks.landed()
    }

    /// A file that won't open (the server's error, a format libmpv doesn't know) ends with an
    /// error before it ever loads, so its entry, not how far it got, says it's this stream's.
    /// The engine ends a stream itself before it stops or replaces it, so a stream libmpv
    /// unloads any other way, as when it shuts down, failed.
    private func ended(_ reason: MPVEndReason) {
        switch reason {
        case .endOfFile where current?.isReady == true:
            reachedEnd()
        case .endOfFile:
            // Unloaded before it ever played.
            fail(MPVError.endedEarly)
        case let .redirected(next?):
            current?.redirect(to: next)
        case .redirected(nil):
            fail(MPVError.emptyPlaylist)
        case let .failed(message):
            fail(MPVError(reason: message))
        case .stopped, .quit:
            fail(MPVError.stopped)
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

    /// With `keep-open`, the last frame stays up at the end, as with AVPlayer, for Up Next. An
    /// end well before the duration is a read or network error (see `isRealEnd(at:of:runtime:)`).
    private func reachedEnd() {
        guard var load = current, load.isReady, !load.hasEnded else { return }
        guard Self.isRealEnd(at: currentTime, of: duration, runtime: load.runtime) else {
            return fail(MPVError.endedEarly)
        }
        load.hasEnded = true
        current = load
        seeks.finishAll(landed: true)
        load.events.yield(.ended)
    }

    /// Fails the stream and ends its events, unless it already played to the end.
    private func fail(_ error: MPVError) {
        if let load = current, !load.hasEnded {
            Logger.mpv.info("stream failed: \(error.reason, privacy: .public)")
            load.events.yield(.failed(PlayerError.streamFailed(underlying: error)))
        }
        endLoad()
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

    /// Ends the current stream's events; seeks waiting for it didn't get there.
    private func endLoad() {
        seeks.finishAll(landed: false)
        current?.events.finish()
        current = nil
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
}
