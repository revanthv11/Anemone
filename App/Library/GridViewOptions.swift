import AnemoneJellyfin
import AnemoneUI
import CoreGraphics

/// How a library grid draws its cards, ported from the parts of Wholphin's `ViewOptions` that
/// fit a TV: the layout, card shape, columns (card size) and titles, and whether the focused
/// title's details and backdrop show.
struct GridViewOptions: Codable, Hashable {
    /// Wholphin's layouts: cards in a grid, or a list of titles with a few details, in two sizes.
    enum Layout: String, Codable, CaseIterable {
        case grid
        case list
        case denseList
    }

    var shape: CardShape
    var columns: Int
    var showTitles = true
    var layout = Layout.grid
    /// Wholphin's "Show details": the focused title's details over the grid, or beside the list.
    var showsDetails = false
    /// Wholphin's "Show backdrop": the focused title's backdrop behind the page.
    var showsBackdrop = false

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

    /// Cards across the grid; a list has one title per row.
    var columnCount: Int {
        layout == .grid ? columns : 1
    }

    /// Between cards, or between a list's rows, which Wholphin spaces 4 dp apart, or 2 dp when dense.
    var itemSpacing: CGFloat {
        switch layout {
        case .grid: spacing
        case .list: 8
        case .denseList: 4
        }
    }

    func cardWidth(in width: CGFloat) -> CGFloat {
        let columns = columnCount
        return max(((width - itemSpacing * CGFloat(columns - 1)) / CGFloat(columns)).rounded(.down), 1)
    }
}

extension GridViewOptions {
    /// Options saved before a field existed get that field's default.
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        shape = try values.decode(CardShape.self, forKey: .shape)
        columns = try values.decode(Int.self, forKey: .columns)
        showTitles = try values.decodeIfPresent(Bool.self, forKey: .showTitles) ?? true
        layout = (try? values.decodeIfPresent(Layout.self, forKey: .layout)) ?? .grid
        showsDetails = try values.decodeIfPresent(Bool.self, forKey: .showsDetails) ?? false
        showsBackdrop = try values.decodeIfPresent(Bool.self, forKey: .showsBackdrop) ?? false
    }
}
