import AnemoneCore
import Foundation
#if os(tvOS) || os(iOS)
    import AVFoundation
    import UIKit
#endif

/// The artwork.
extension NowPlaying {
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
