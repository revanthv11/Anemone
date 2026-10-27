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
    /// (`showsInSystemPlayer`).
    public var usesSystemPlayer: Bool?
    /// What this feature publishes; `nil` while the system player publishes instead.
    public private(set) var info: NowPlayingInfo?

    private let center: any NowPlayingCenter
    private let loadArtwork: ArtworkLoader
    private weak var controller: PlaybackController?
    /// The artwork loaded, or loading, kept for a retry as a transcode.
    private var artworkURL: URL?
    private var artwork: Data?
    private var artworkTask: Task<Void, Never>?

    private static let log = Logger(subsystem: "com.revanthv11.anemone", category: "Playback")

    public convenience init() {
        self.init(center: SystemNowPlayingCenter()) { url in
            await Self.download(url)
        }
    }

    init(center: any NowPlayingCenter, loadArtwork: @escaping ArtworkLoader) {
        self.center = center
        self.loadArtwork = loadArtwork
    }

    public func handle(_ event: PlaybackEvent, in controller: PlaybackController) async {
        self.controller = controller
        switch event {
        case let .loaded(stream, entry):
            let method = String(describing: stream.method)
            Self.log.notice("Playing \(entry.itemID, privacy: .public) by \(method, privacy: .public)")
            loaded(entry, in: controller)
        case let .started(progress), let .position(progress), let .paused(progress), let .resumed(progress):
            update(position: progress.position, isPlaying: !progress.isPaused)
        case .stopped:
            stopPublishing()
        case .ended, .failed:
            break
        }
    }

    private func loaded(_ entry: PlaybackQueue.Entry, in controller: PlaybackController) {
        if entry.metadata.artworkURL != artworkURL {
            loadArtwork(from: entry.metadata.artworkURL)
        }
        guard !(usesSystemPlayer ?? controller.engine.showsInSystemPlayer) else {
            stopPublishing()
            showInSystemPlayer()
            return
        }
        let queue = controller.queue
        info = NowPlayingInfo(
            metadata: entry.metadata,
            artwork: artwork,
            position: entry.startPosition ?? .zero,
            duration: controller.engine.duration,
            rate: controller.engine.rate,
            // Intros aren't counted (Phase 5c).
            queueIndex: queue.indexWithoutIntros,
            queueCount: queue.countWithoutIntros,
        )
        center.publish(info)
        handleCommands(for: queue)
    }

    private func handleCommands(for queue: PlaybackQueue) {
        center.handle(Self.commands(for: queue), skipIntervals: (Self.skipForward, Self.skipBackward)) { [weak self] in
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

    private func update(position: Duration, isPlaying: Bool) {
        guard var info, let controller else { return }
        let engine = controller.engine
        info.position = position
        info.isPlaying = isPlaying
        info.duration = engine.duration
        info.rate = engine.rate
        // An episode's queue grows once the episodes after it are found, so Next can come on.
        let queue = controller.queue
        if info.queueCount != queue.countWithoutIntros {
            info.queueCount = queue.countWithoutIntros
            info.queueIndex = queue.indexWithoutIntros
            handleCommands(for: queue)
        }
        publish(info)
    }

    private func publish(_ info: NowPlayingInfo) {
        guard info != self.info else { return }
        self.info = info
        center.publish(info)
    }

    private func stopPublishing() {
        guard info != nil else { return }
        info = nil
        center.stopHandling()
        center.publish(nil)
    }

    /// What the remote asked for; `false` when it can't be done.
    private func perform(_ request: RemoteRequest) -> Bool {
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
        guard var info, let engine = controller?.engine else { return }
        var target = max(position, .zero)
        if let duration = engine.duration {
            target = min(target, duration)
        }
        info.position = target
        publish(info)
        Task {
            _ = await engine.seek(to: target)
        }
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
            artwork = data
            if var info {
                info.artwork = data
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
            guard let artwork, let item = (controller?.engine as? AVPlayerEngine)?.player.currentItem else { return }
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
