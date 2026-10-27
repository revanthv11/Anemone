import Foundation
import Nuke

public extension ArtworkImage {
    /// Loads an image into the cache, so the next `ArtworkImage` for it draws at once, as
    /// Wholphin's screensaver loads each backdrop before showing it. Failures are ignored; the
    /// image then loads when shown.
    static func preload(_ url: URL) async {
        _ = try? await ImagePipeline.shared.image(for: url)
    }
}
