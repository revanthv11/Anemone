import Foundation

/// What the player shows about an entry: in AVKit's title view and info panel, and in Now
/// Playing. Engines turn it into their own form, so it says nothing about any one player.
public struct PlaybackMetadata: Hashable, Sendable {
    public var title: String
    /// For episodes, the episode under the series' title.
    public var subtitle: String?
    public var overview: String?
    /// Artwork for Now Playing; not shown yet.
    public var artworkURL: URL?

    public init(title: String, subtitle: String? = nil, overview: String? = nil, artworkURL: URL? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.overview = overview
        self.artworkURL = artworkURL
    }
}
