import AnemoneJellyfin
import Foundation
import os

/// Now Playing: the title, artwork and position the system shows for what's playing, and the
/// remote's commands (play, pause, skips, scrubbing, and next and previous when the queue has
/// more than one entry). Ported from Wholphin's media session (`PlaybackViewModel` and
/// `toMediaMetadata`), with the commands adapted from Swiftfin's `NowPlayableObserver`.
///
/// AVKit's system player publishes Now Playing and answers the remote itself, reading the AVPlayer
/// item's metadata, so with it this feature only adds the artwork there. Anemone's overlay and
/// MPV (Phase 4) have nothing doing that for them, so with them it publishes everything.
///
/// Music gets one per `MusicPlayer`, which every song's controller shares. Each song plays in a
/// controller of its own, holding a queue of one, so the player keeps the queue: Now Playing
/// shows the song's place in the player's queue and sends the remote's commands to the player,
/// as Wholphin's `MusicService` media session does. It stays while the music moves from one song
/// to the next, and while it waits at the end of its queue, where Play starts it again.
@MainActor
public final class NowPlaying: PlaybackFeature {
    typealias ArtworkLoader = @Sendable (URL) async -> Data?

    /// Wholphin's default skips, forward 30 s and back 10 s.
    public static let skipForward = Duration.seconds(30)
    public static let skipBackward = Duration.seconds(10)
    /// Like Wholphin's Previous, which uses Media3's `seekToPrevious`: early on, it plays the entry
    /// before; later, it goes back to the start of this one.
    static let previousEntryWindow = Duration.seconds(3)

    /// Whether AVKit's system player shows the video; when `nil`, as `PlayerScreen` chooses
    /// (`showsInSystemPlayer`). Never for music, which has no video.
    public var usesSystemPlayer: Bool?
    /// What this feature publishes; `nil` while the system player publishes instead.
    public private(set) var info: NowPlayingInfo?

    let slot: Slot
    let loadArtwork: ArtworkLoader
    /// For music: the player whose songs this shows.
    let isMusic: Bool
    private(set) weak var music: MusicPlayer?
    /// The controller that loaded last. A song's controller that the next song replaced can still
    /// be closing; what it says is dropped.
    private(set) weak var controller: PlaybackController?
    /// The artwork loaded, or loading, kept for a retry as a transcode (and for the next song
    /// when it's on the same album).
    var artworkURL: URL?
    var artwork: NowPlayingArtwork?
    var artworkTask: Task<Void, Never>?
    /// The commands handed to the remote, so they're handed over again only when they change.
    var handledCommands: Set<RemoteCommand>?

    private static let log = Logger(subsystem: "com.revanthv11.anemone", category: "Playback")

    public convenience init() {
        self.init(slot: .shared) { url in
            await Self.download(url)
        }
    }

    /// Now Playing for the songs `player` plays.
    convenience init(music player: MusicPlayer, slot: Slot = .shared) {
        self.init(slot: slot, music: player) { url in
            await Self.download(url)
        }
    }

    /// With a center of its own, which no other player shares.
    convenience init(center: any NowPlayingCenter, loadArtwork: @escaping ArtworkLoader) {
        self.init(slot: Slot(center: center), loadArtwork: loadArtwork)
    }

    init(slot: Slot, music: MusicPlayer? = nil, loadArtwork: @escaping ArtworkLoader) {
        self.slot = slot
        self.music = music
        isMusic = music != nil
        self.loadArtwork = loadArtwork
        if isMusic {
            usesSystemPlayer = false
        }
    }

    public func handle(_ event: PlaybackEvent, in controller: PlaybackController) async {
        switch event {
        case let .loaded(stream, entry):
            self.controller = controller
            let method = String(describing: stream.method)
            Self.log.notice("Playing \(entry.itemID, privacy: .public) by \(method, privacy: .public)")
            loaded(entry, in: controller)
        case .reloaded:
            loaded(controller.queue.current, in: controller)
        case let .started(progress), let .position(progress), let .paused(progress), let .resumed(progress):
            guard controller === self.controller else { return }
            update(position: progress.position, isPlaying: !progress.isPaused)
        case .ended:
            // The last song of a queue stays, stopped at its end.
            guard isMusic, controller === self.controller, let end = controller.engine.duration ?? info?.duration
            else { return }
            update(position: end, isPlaying: false)
        case .failed:
            // A song the server couldn't send shows, as the music player does, rather than the
            // song before it.
            guard isMusic, controller !== self.controller else { return }
            self.controller = controller
            loaded(controller.queue.current, in: controller)
        case .stopped:
            guard controller === self.controller else { return }
            stopped()
        }
    }

    /// Clears what this feature published, unless another player or song has published since.
    func stopPublishing() {
        guard info != nil else { return }
        info = nil
        handledCommands = nil
        slot.release(by: self)
    }

    private func loaded(_ entry: PlaybackQueue.Entry, in controller: PlaybackController) {
        if entry.metadata.artworkURL != artworkURL {
            loadArtwork(from: entry.metadata.artworkURL)
        }
        guard !(usesSystemPlayer ?? controller.engine.showsInSystemPlayer) else {
            stopPublishing()
            slot.yield(to: self)
            showInSystemPlayer()
            return
        }
        let place = queuePlace(in: controller)
        let shown = NowPlayingInfo(
            metadata: entry.metadata,
            artwork: artwork,
            position: entry.startPosition ?? .zero,
            duration: controller.engine.duration ?? music?.duration,
            rate: controller.engine.rate,
            queueIndex: place.index,
            queueCount: place.count,
            isMusic: isMusic,
            album: music?.current.flatMap { $0.id == entry.itemID ? $0.albumName : nil },
        )
        info = shown
        // Again, even when it's the same: another player may have published since.
        slot.publish(shown, by: self)
        handledCommands = nil
        handleCommands(in: controller)
    }

    /// For music, the song stopped as the player moves on to the next, whose `loaded` takes over,
    /// as a new queue loads, or as the player waits at the end of its queue: Now Playing and the
    /// remote's commands stay, so the last song shows until the next one does and Play can start
    /// the queue again. The player's `stop()` clears them. Otherwise it's cleared.
    private func stopped() {
        if isMusic, let music, music.status != .idle {
            return
        }
        stopPublishing()
    }

    /// For music: the player's queue changed (songs added, moved or removed, shuffle or repeat),
    /// so the song's place and Next follow at once, also at the end of the queue, where no song's
    /// events come to update them.
    func musicQueueChanged() {
        guard var info, let music, let index = music.queue.currentIndex else { return }
        info.queueIndex = index
        info.queueCount = music.queue.entries.count
        publish(info)
        handleCommands(in: controller)
    }

    /// Shows `position` at once, rather than at the next position event, as for a seek.
    func show(position: Duration) {
        guard var info else { return }
        info.position = position
        publish(info)
    }

    /// The entry's place in its queue, not counting intros (Phase 5c): the music player's for a
    /// song.
    private func queuePlace(in controller: PlaybackController) -> (index: Int, count: Int) {
        if let music, let index = music.queue.currentIndex {
            return (index, music.queue.entries.count)
        }
        return (controller.queue.indexWithoutIntros, controller.queue.countWithoutIntros)
    }

    private func update(position: Duration, isPlaying: Bool) {
        guard var info, let controller else { return }
        let engine = controller.engine
        // While a song's seek is on its way, its engine still tells the old time: the target
        // shows meanwhile, as on the Now Playing page.
        info.position = music.flatMap { $0.isSeeking ? $0.position : nil } ?? position
        info.isPlaying = isPlaying
        info.duration = engine.duration ?? info.duration
        info.rate = engine.rate
        // An episode's queue grows once the episodes after it are found, so Next can come on; a
        // song's place moves with the music player's queue.
        let place = queuePlace(in: controller)
        info.queueIndex = place.index
        info.queueCount = place.count
        handleCommands(in: controller)
        publish(info)
    }

    func publish(_ info: NowPlayingInfo) {
        guard info != self.info else { return }
        self.info = info
        slot.publish(info, by: self)
    }
}
