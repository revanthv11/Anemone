import Nuke
import NukeUI
import SwiftUI

/// Artwork from the server, loaded and cached by Nuke. Draws nothing until the image arrives,
/// so callers put their placeholder behind it.
public struct ArtworkImage: View {
    private let url: URL?

    public init(url: URL?) {
        self.url = url
    }

    public var body: some View {
        LazyImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { state in
            if let image = state.image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Color.clear
            }
        }
    }

    /// Keeps downloaded artwork on disk, ignoring HTTP cache headers. Image URLs carry the
    /// image's tag, which changes whenever the image does, so a cached copy is never stale.
    /// Call once at launch.
    public static func configureCache() {
        ImagePipeline.shared = ImagePipeline(
            configuration: .withDataCache(name: "com.revanthv11.anemone.artwork", sizeLimit: 500 * 1024 * 1024),
        )
    }
}
