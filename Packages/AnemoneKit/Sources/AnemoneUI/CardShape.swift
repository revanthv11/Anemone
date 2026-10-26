import SwiftUI

/// The image shapes used for cards in rows and grids, matching Wholphin's poster/thumb options.
public enum CardShape: String, CaseIterable, Codable, Sendable {
    /// Portrait poster art.
    case poster
    /// Landscape thumbnails, used for episodes and the "thumb" display style.
    case thumb
    /// Album art, people and playlists.
    case square

    public var aspectRatio: CGFloat {
        switch self {
        case .poster: 2.0 / 3.0
        case .thumb: 16.0 / 9.0
        case .square: 1
        }
    }
}
