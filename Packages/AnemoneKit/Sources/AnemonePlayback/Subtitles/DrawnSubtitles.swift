import AnemoneCore
import AnemoneJellyfin
import Foundation
import Observation
import os

/// Text subtitles that Anemone draws over the video itself, in the user's subtitle style.
///
/// AVPlayer showed the WebVTT in Jellyfin's HLS playlists 10 s late in remuxed streams (the
/// segments map their times with `X-TIMESTAMP-MAP=MPEGTS:900000`, but the video starts at 0;
/// see `docs/upstream/jellyfin-hls-webvtt-offset.md`). So the server sends text subtitles as
/// files of their own (`AVPlayerProfile`'s External delivery), this fetches the one chosen
/// whole, and both player screens draw what shows at the playing position
/// (`App/Playback/Subtitles`). Switching between text subtitles then needs no new stream.
///
/// `TrackSelection` says what to draw with `show(_:in:)`, whichever of the two hears of a new
/// stream first. Picture subtitles, and ASS on AVPlayer,
/// are still burned in by the server, and subtitles inside a file AVPlayer plays directly (MP4's
/// own text) are still the player's. Nothing is drawn while MPV plays: MPV adds the files the
/// server sends beside its stream to its own tracks and shows them itself
/// (`MPVExternalSubtitles`), with libass and MPV's own delay.
@MainActor
@Observable
public final class DrawnSubtitles: PlaybackFeature {
    /// What the feature asks the server; tests stand in for it.
    struct Server: Sendable {
        var timeline: @Sendable (SubtitleFileRequest) async throws -> SubtitleTimeline
    }

    static let delayMenuID = "drawnSubtitleDelay"
    /// The longest a follower waits before looking at the position again, so a seek, a pause or
    /// a new delay shows within a quarter of a second.
    static let longestWait = Duration.milliseconds(250)

    /// The track drawn, if any.
    public private(set) var track: MediaTrack?
    /// What shows at the position `update(at:)` was last given, oldest first.
    public private(set) var cues: [SubtitleCue] = []
    /// The user's style, or their HDR style for HDR video.
    public private(set) var style = SubtitleStyle.standard
    /// The entry's subtitle delay: later when positive. Each entry starts without one, as in
    /// Wholphin. MPV has its own for what it shows, in its own menu (`MPVSubtitleMenus`).
    public private(set) var delay = Duration.zero

    @ObservationIgnored private let server: Server
    @ObservationIgnored private weak var controller: PlaybackController?
    /// The stream playing, from its `loaded` or `reloaded` until its `stopped`.
    @ObservationIgnored private var stream: PlaybackStream?
    /// What `show(_:in:)` was asked to draw for a stream this hadn't heard of yet: features hear
    /// of a new stream in turn, and track selection can ask while one before this is busy.
    @ObservationIgnored private var wanted: (track: MediaTrack?, stream: PlaybackStream)?
    /// The streams heard of that another has replaced, or that stopped, for this player: what
    /// `show(_:in:)` is asked for one of them is late, not early, and draws nothing.
    @ObservationIgnored private var replaced: Set<PlaybackStream> = []
    @ObservationIgnored private var request: SubtitleFileRequest?
    @ObservationIgnored private var timeline: SubtitleTimeline?
    /// Files already read for this player, so a reload for another audio track, or switching back,
    /// doesn't fetch them again.
    @ObservationIgnored private var read: [SubtitleFileRequest: SubtitleTimeline] = [:]
    @ObservationIgnored private var loading: Task<Void, Never>?

    public convenience init(session: JellyfinSession) {
        self.init(server: Server(timeline: { request in
            let file = try await session.subtitleFile(request)
            return SubtitleTimeline(parsing: file.text, format: file.format)
        }))
    }

    init(server: Server) {
        self.server = server
    }

    public func handle(_ event: PlaybackEvent, in controller: PlaybackController) async {
        self.controller = controller
        switch event {
        case let .loaded(stream, _):
            delay = .zero
            begin(stream)
        case let .reloaded(stream):
            begin(stream)
        case .stopped:
            if let stream {
                replaced.insert(stream)
            }
            stream = nil
            wanted = nil
            clear()
            if controller.isStopped {
                read = [:]
                replaced = []
            }
        default:
            break
        }
    }

    /// Nothing is drawn for a new stream until `TrackSelection` says what to draw, unless it
    /// already has.
    private func begin(_ stream: PlaybackStream) {
        if let old = self.stream {
            replaced.insert(old)
        }
        replaced.remove(stream)
        self.stream = stream
        style = SubtitleStyles.current.style(forHDR: stream.isHDR)
        clear()
        if let wanted, wanted.stream == stream {
            show(wanted.track, in: stream)
        }
        wanted = nil
    }

    /// Draws `track`, a text subtitle that `stream` sends as a file of its own, or nothing. Asked
    /// for a stream before this has heard of it, it draws it once it does; asked for one that's
    /// been replaced, nothing, and what's waiting for the next stream stays. While MPV plays,
    /// it draws nothing, since MPV shows that file itself.
    public func show(_ track: MediaTrack?, in stream: PlaybackStream) {
        guard stream == self.stream else {
            if !replaced.contains(stream) {
                wanted = (track, stream)
            }
            return
        }
        wanted = nil
        guard let track, track.kind == .subtitle, track.isText, controller?.engine.mpv == nil else {
            clear()
            return
        }
        let request = SubtitleFileRequest(
            track,
            itemID: stream.itemID,
            mediaSourceID: stream.mediaSourceID ?? stream.itemID,
        )
        guard request != self.request else { return }
        clear()
        self.request = request
        self.track = track
        if let known = read[request] {
            timeline = known
            showMenu()
            return
        }
        // The delay menu shows once there's something to delay.
        loading = Task { [weak self, server] in
            do {
                let timeline = try await server.timeline(request)
                guard let self, !Task.isCancelled, self.request == request else { return }
                read[request] = timeline
                self.timeline = timeline
                showMenu()
            } catch {
                guard let self, !Task.isCancelled, self.request == request else { return }
                let index = request.index
                Self.log.error("Couldn't fetch subtitles \(index, privacy: .public): \(error, privacy: .public)")
                // Nothing to draw, and asking for the track again fetches it again.
                clear()
            }
        }
    }

    private func clear() {
        loading?.cancel()
        loading = nil
        request = nil
        track = nil
        timeline = nil
        if !cues.isEmpty {
            cues = []
        }
        controller?.accessories.removeMenu(Self.delayMenuID)
    }

    /// Shows the cues at `position` in the stream, shifted by the delay. Returns how long it is,
    /// at normal speed, until what shows changes; `nil` when nothing more will show.
    @discardableResult
    public func update(at position: Duration) -> Duration? {
        guard let timeline else {
            if !cues.isEmpty {
                cues = []
            }
            return nil
        }
        let time = position - delay
        let showing = timeline.cues(at: time)
        if showing != cues {
            cues = showing
        }
        return timeline.nextChange(after: time).map { $0 - time }
    }

    /// Keeps `cues` up to date with the engine's position until cancelled, as a player screen
    /// does while it shows them: wakes when the next cue starts or one ends, and at least every
    /// `longestWait`.
    public func follow() async {
        while !Task.isCancelled {
            var wait = Self.longestWait
            if let engine = controller?.engine, let change = update(at: engine.currentTime) {
                wait = min(wait, change / Double(max(engine.rate, 0.25)))
            }
            try? await Task.sleep(for: max(wait, .milliseconds(10)))
        }
    }

    // MARK: - Delay

    /// Wholphin's subtitle delay steps, as MPV's menu offers them, while subtitles are drawn.
    private func showMenu() {
        guard let controller else { return }
        guard track != nil, timeline != nil else {
            controller.accessories.removeMenu(Self.delayMenuID)
            return
        }
        let later = MPVSubtitleMenus.delaySteps
        let steps = later.reversed().map { .zero - $0 } + [.zero] + later
        controller.accessories.show(PlayerMenu(
            id: Self.delayMenuID,
            title: "Subtitle delay: \(MPVSubtitleMenus.delayText(delay))",
            systemImage: "timer",
            options: steps.map { step in
                PlayerMenu.Option(
                    id: step == .zero ? "reset" : MPVSubtitleMenus.delayText(step),
                    title: step == .zero ? "No delay" : MPVSubtitleMenus.delayText(step),
                    isSelected: step == .zero && delay == .zero,
                ) { [weak self] in
                    self?.changeDelay(by: step)
                }
            },
        ))
    }

    /// Adds `step` to the delay; zero resets it.
    func changeDelay(by step: Duration) {
        delay = step == .zero ? .zero : delay + step
        showMenu()
    }

    private static let log = Logger(subsystem: "com.revanthv11.anemone", category: "Subtitles")
}

extension PlaybackStream {
    /// Whether the video is HDR or Dolby Vision, which takes the HDR subtitle style.
    var isHDR: Bool {
        guard let range = video?.range else { return false }
        return ![.sdr, .unknown, .doviWithSDR].contains(range)
    }
}
