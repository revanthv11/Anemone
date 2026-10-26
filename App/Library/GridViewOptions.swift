import AnemoneJellyfin
import AnemoneUI
import CoreGraphics

/// How a library grid draws its cards, ported from the parts of Wholphin's `ViewOptions` that
/// fit a TV grid: card shape, columns (card size) and titles.
struct GridViewOptions: Codable, Hashable {
    var shape: CardShape
    var columns: Int
    var showTitles = true

    /// Wholphin's column choices, less one column, which makes a single poster taller than the screen.
    static let columnChoices = Array(2 ... 12)

    /// Wholphin's defaults: posters for movies, shows and collections; squares for music and
    /// playlists; 16:9 thumbs for everything else.
    static func defaults(for kind: Library.Kind) -> GridViewOptions {
        switch kind {
        case .movies, .shows, .collections:
            GridViewOptions(shape: .poster, columns: 6)
        case .music, .playlists:
            GridViewOptions(shape: .square, columns: 6)
        default:
            GridViewOptions(shape: .thumb, columns: 4)
        }
    }

    /// Wholphin spaces poster and square grids 16 dp apart and thumb grids 24 dp; doubled here
    /// for a 1920-point screen.
    var spacing: CGFloat {
        shape == .thumb ? 48 : 32
    }

    func cardWidth(in width: CGFloat) -> CGFloat {
        max(((width - spacing * CGFloat(columns - 1)) / CGFloat(columns)).rounded(.down), 1)
    }
}
