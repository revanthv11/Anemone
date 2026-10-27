import AnemoneJellyfin
import Foundation
#if os(tvOS) || os(iOS)
    import MediaPlayer
    import UIKit
#endif

/// What shows the music player outside the app and takes the remote's commands while it's in
/// the background: Now Playing, in place of Wholphin's `MediaSession`.
///
/// Anemone's video player gets its Now Playing from a playback feature (Phase 3f); music can
/// move to it by giving each song's controller that feature and keeping Next and Previous here.
@MainActor
public protocol MusicRemote: AnyObject {
    /// The player started a queue; commands act on it from now on.
    func attach(to player: MusicPlayer)
    /// The song, its position or the status changed.
    func update(from player: MusicPlayer)
    /// The player stopped.
    func detach()
}

#if os(tvOS) || os(iOS)
    /// The system's Now Playing and remote commands for the music player.
    @MainActor
    public final class NowPlayingRemote: MusicRemote {
        /// Where a song's artwork comes from.
        public typealias ArtworkURL = @MainActor (MusicItem) -> URL?

        private let artworkURL: ArtworkURL
        private weak var player: MusicPlayer?
        private var targets: [(MPRemoteCommand, Any)] = []
        private var artwork: (songID: String, image: MPMediaItemArtwork?)?
        private var artworkTask: Task<Void, Never>?

        public init(artworkURL: @escaping ArtworkURL) {
            self.artworkURL = artworkURL
        }

        public func attach(to player: MusicPlayer) {
            self.player = player
            guard targets.isEmpty else { return }
            let center = MPRemoteCommandCenter.shared()
            add(center.playCommand) { $0.resume() }
            add(center.pauseCommand) { $0.pause() }
            add(center.togglePlayPauseCommand) { $0.togglePlayPause() }
            add(center.nextTrackCommand) { $0.next() }
            add(center.previousTrackCommand) { $0.previous() }
            add(center.changePlaybackPositionCommand) { player, position in
                if let position {
                    player.seek(to: .seconds(position))
                }
            }
        }

        public func update(from player: MusicPlayer) {
            guard let song = player.current else {
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
                return
            }
            var info: [String: Any] = [
                MPMediaItemPropertyTitle: song.item.name,
                MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
                MPNowPlayingInfoPropertyElapsedPlaybackTime: player.position / .seconds(1),
                MPNowPlayingInfoPropertyPlaybackRate: player.status == .playing ? 1.0 : 0.0,
            ]
            info[MPMediaItemPropertyArtist] = song.artistNames
            info[MPMediaItemPropertyAlbumTitle] = song.albumName
            if let duration = player.duration ?? song.item.runtime {
                info[MPMediaItemPropertyPlaybackDuration] = duration / .seconds(1)
            }
            if let index = player.queue.currentIndex {
                info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = index
                info[MPNowPlayingInfoPropertyPlaybackQueueCount] = player.queue.entries.count
            }
            if let artwork, artwork.songID == song.id {
                info[MPMediaItemPropertyArtwork] = artwork.image
            } else {
                loadArtwork(for: song)
            }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }

        /// Takes the commands away as well as their targets, so the system stops offering
        /// controls that nothing answers.
        public func detach() {
            for (command, target) in targets {
                command.removeTarget(target)
                command.isEnabled = false
            }
            targets = []
            player = nil
            artworkTask?.cancel()
            artworkTask = nil
            artwork = nil
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }

        private func add(_ command: MPRemoteCommand, _ action: @escaping @MainActor (MusicPlayer) -> Void) {
            add(command) { player, _ in action(player) }
        }

        /// `action` gets the position a scrub asked for, if the command was one.
        private func add(
            _ command: MPRemoteCommand,
            _ action: @escaping @MainActor (MusicPlayer, TimeInterval?) -> Void,
        ) {
            command.isEnabled = true
            // The center calls back on the main thread, but says nothing about isolation.
            let target = command.addTarget { @Sendable [weak self] event in
                let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime
                Task { @MainActor in
                    if let player = self?.player {
                        action(player, position)
                    }
                }
                return .success
            }
            targets.append((command, target))
        }

        /// Made outside the main actor: Now Playing asks for the image on a queue of its own.
        private nonisolated static func artwork(_ image: UIImage) -> MPMediaItemArtwork {
            MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }

        /// Fetches the cover once per song, then shows it.
        private func loadArtwork(for song: MusicItem) {
            artwork = (song.id, nil)
            artworkTask?.cancel()
            guard let url = artworkURL(song) else { return }
            artworkTask = Task { [weak self] in
                guard let (data, _) = try? await URLSession.shared.data(from: url),
                      let image = UIImage(data: data),
                      !Task.isCancelled
                else { return }
                let artwork = Self.artwork(image)
                guard let self, self.artwork?.songID == song.id, let player else { return }
                self.artwork = (song.id, artwork)
                update(from: player)
            }
        }
    }
#endif
