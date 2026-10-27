import AnemoneCore
import AnemoneJellyfin
import Foundation
import os
#if os(tvOS) || os(iOS)
    import AVFoundation
    import UIKit
#endif

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

    private let slot: Slot
    private let loadArtwork: ArtworkLoader
    /// For music: the player whose songs this shows.
    private let isMusic: Bool
    private weak var music: MusicPlayer?
    /// The controller that loaded last. A song's controller that the next song replaced can still
    /// be closing; what it says is dropped.
    private weak var controller: PlaybackController?
    /// The artwork loaded, or loading, kept for a retry as a transcode (and for the next song
    /// when it's on the same album).
    private var artworkURL: URL?
    private var artwork: NowPlayingArtwork?
    private var artworkTask: Task<Void, Never>?
    /// The commands handed to the remote, so they're handed over again only when they change.
    private var handledCommands: Set<RemoteCommand>?

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
    /// or as it waits at the end of its queue: Now Playing and the remote's commands stay, so Play
    /// can start the queue again. Otherwise it's cleared.
    private func stopped() {
        if isMusic, music?.hasQueue == true {
            return
        }
        stopPublishing()
    }

    private func handleCommands(in controller: PlaybackController) {
        let commands = music.map(Self.commands(for:)) ?? Self.commands(for: controller.queue)
        guard commands != handledCommands else { return }
        handledCommands = commands
        slot.handle(commands, skipIntervals: (Self.skipForward, Self.skipBackward), by: self) { [weak self] in
            self?.perform($0) ?? false
        }
    }

    /// Next only when there's an entry after this one; Previous whenever the queue has several,
    /// since on the first entry it goes back to the start. Intros don't count, but Next during
    /// one moves on to what it leads into.
    static func commands(for queue: PlaybackQueue) -> Set<RemoteCommand> {
        var commands: Set<RemoteCommand> = [
            .play, .pause, .togglePlayPause, .skipForward, .skipBackward, .changePosition,
        ]
        if queue.countWithoutIntros > 1 {
            commands.insert(.previousTrack)
        }
        if queue.next != nil {
            commands.insert(.nextTrack)
        }
        return commands
    }

    /// For music, Next when the queue has a song after this one (or starts again); Previous always,
    /// since it goes back to the start of the song. No skips, so the system offers the track
    /// buttons, as it did before music moved onto this feature.
    static func commands(for player: MusicPlayer) -> Set<RemoteCommand> {
        var commands: Set<RemoteCommand> = [.play, .pause, .togglePlayPause, .changePosition, .previousTrack]
        if player.queue.nextIndex(automatic: false) != nil {
            commands.insert(.nextTrack)
        }
        return commands
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
        info.position = position
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

    private func publish(_ info: NowPlayingInfo) {
        guard info != self.info else { return }
        self.info = info
        slot.publish(info, by: self)
    }

    /// What the remote asked for; `false` when it can't be done.
    private func perform(_ request: RemoteRequest) -> Bool {
        if isMusic {
            return music.map { perform(request, on: $0) } ?? false
        }
        guard let info, let controller else { return false }
        // Someone's there, so pass-out protection starts counting again.
        controller.feature(UpNext.self)?.noteRemoteInput()
        let engine = controller.engine
        switch request {
        case .play:
            engine.play()
        case .pause:
            engine.pause()
        case .togglePlayPause:
            return perform(info.isPlaying ? .pause : .play)
        case let .skip(offset):
            seek(to: engine.currentTime + offset)
        case let .seek(position):
            seek(to: position)
        case .next:
            guard controller.queue.next != nil else { return false }
            // The queue moves on through the controller, as Up Next does (Phase 3b).
            controller.playNext()
        case .previous:
            playPrevious(in: controller)
        }
        return true
    }

    /// Everything goes to the music player, which keeps the queue, and knows whether a song still
    /// loading should start once it's ready (`SongEngine`).
    private func perform(_ request: RemoteRequest, on player: MusicPlayer) -> Bool {
        switch request {
        case .play:
            player.resume()
        case .pause:
            player.pause()
        case .togglePlayPause:
            player.togglePlayPause()
        case let .skip(offset):
            player.skip(by: offset)
            show(position: player.position)
        case let .seek(position):
            player.seek(to: position)
            show(position: player.position)
        case .next:
            guard player.queue.nextIndex(automatic: false) != nil else { return false }
            player.next()
        case .previous:
            player.previous()
        }
        return true
    }

    /// The entry before, passing over intros.
    private func playPrevious(in controller: PlaybackController) {
        if controller.engine.currentTime < Self.previousEntryWindow, let index = controller.queue.previousIndex {
            controller.play(entryAt: index)
        } else {
            seek(to: .zero)
        }
    }

    /// Within the video, and shown at once rather than at the next position event.
    private func seek(to position: Duration) {
        guard let engine = controller?.engine else { return }
        var target = max(position, .zero)
        if let duration = engine.duration {
            target = min(target, duration)
        }
        show(position: target)
        Task {
            _ = await engine.seek(to: target)
        }
    }

    private func show(position: Duration) {
        guard var info else { return }
        info.position = position
        publish(info)
    }
}

/// The artwork.
private extension NowPlaying {
    func loadArtwork(from url: URL?) {
        artworkTask?.cancel()
        artworkURL = url
        artwork = nil
        guard let url else { return }
        let load = loadArtwork
        artworkTask = Task { [weak self] in
            let data = await load(url)
            guard !Task.isCancelled, let self, let data else { return }
            let loaded = NowPlayingArtwork(url: url, data: data)
            artwork = loaded
            if var info {
                info.artwork = loaded
                publish(info)
            } else {
                showInSystemPlayer()
            }
        }
    }

    /// AVKit's info panel and Now Playing read the artwork from the item's metadata, as they read
    /// its title, so for AVPlayer it goes there too.
    func showInSystemPlayer() {
        #if os(tvOS) || os(iOS)
            guard let artwork = artwork?.data,
                  let item = (controller?.engine as? AVPlayerEngine)?.player.currentItem
            else { return }
            let metadata = AVMutableMetadataItem()
            metadata.identifier = .commonIdentifierArtwork
            metadata.extendedLanguageTag = "und"
            if artwork.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
                metadata.value = artwork as NSData
                metadata.dataType = kCMMetadataBaseDataType_PNG as String
            } else if artwork.starts(with: [0xFF, 0xD8]) {
                metadata.value = artwork as NSData
                metadata.dataType = kCMMetadataBaseDataType_JPEG as String
            } else if let png = UIImage(data: artwork)?.pngData() {
                // Such as WebP, which the metadata can't hold.
                metadata.value = png as NSData
                metadata.dataType = kCMMetadataBaseDataType_PNG as String
            } else {
                return
            }
            item.externalMetadata = item.externalMetadata.filter { $0.identifier != .commonIdentifierArtwork }
                + [metadata]
        #endif
    }

    /// `nil` when the server has no such image.
    nonisolated static func download(_ url: URL) async -> Data? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return data
    }
}

extension PlayerEngine {
    /// Whether AVKit's system player shows this engine's video, as `PlayerScreen` chooses: for
    /// AVPlayer, unless Settings › Playback › Player Controls asks for Anemone's overlay.
    var showsInSystemPlayer: Bool {
        guard case .avPlayer = videoOutput else { return false }
        return Preferences.playerControls.value() == .system
    }
}
