import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// Cards for a library's titles: posters, thumbs or squares in the grid, or rows in a list.
/// Grid cards can open the app's long-press card menu.
struct LibraryCard: View {
    let entry: LibraryEntry?
    let options: GridViewOptions
    let width: CGFloat
    let imageURL: URL?
    /// Whether the card gives the card menu its item; see `LibraryGrid.showsCardMenu`.
    var showsMenu = false

    var body: some View {
        let item = entry?.item
        switch options.layout {
        case .grid:
            MediaCard(
                title: item?.displayTitle ?? " ",
                subtitle: item.flatMap { $0.subtitle ?? $0.year.map(String.init) },
                spokenSubtitle: item?.spokenSubtitle,
                imageURL: imageURL,
                shape: options.shape,
                width: width,
                progress: item?.progress,
                badges: entry?.details?.badges ?? CardBadges(),
                showsCaption: options.showTitles,
                menuItem: menuItem,
            )
        case .list, .denseList:
            LibraryListRow(entry: entry, isDense: options.layout == .denseList, showsMenu: showsMenu)
                .frame(width: width)
        }
    }

    /// The entry's details when it has them, so the menu knows whether it's watched or a
    /// favourite; none while its page loads.
    private var menuItem: CardMenuItem? {
        guard showsMenu, let entry else { return nil }
        return entry.cardMenuItem
    }
}

extension LibraryEntry {
    /// What the card menu is given: the entry's details when it has them, so the menu knows
    /// whether it's watched or a favourite, else the item alone.
    var cardMenuItem: CardMenuItem {
        details.map { CardMenuItem($0) } ?? CardMenuItem(item)
    }
}

extension LibraryGrid where Card == LibraryCard {
    /// A grid of a library's titles, drawn as `options` says. Its cards open the card menu only
    /// with `showsCardMenu`, which the library pages turn on.
    init(
        pager: LibraryPager,
        options: GridViewOptions,
        showsJumpBar: Bool,
        position: @escaping (Character) async throws -> Int,
        imageURL: @escaping (_ item: MediaItem, _ shape: CardShape, _ pixelWidth: Int) -> URL?,
        onSelect: @escaping (MediaItem) -> Void,
        onFocus: @escaping (Int) -> Void = { _ in },
        onPastFirstRow: @escaping (Bool) -> Void = { _ in },
        onExitTop: (() -> Void)? = nil,
        emptyMessage: String? = nil,
        hearsPageButtons: Bool = false,
        showsCardMenu: Bool = false,
        @ViewBuilder header: () -> Header,
    ) {
        self.init(
            pager: pager,
            options: options,
            showsJumpBar: showsJumpBar,
            position: position,
            onSelect: onSelect,
            onFocus: onFocus,
            onPastFirstRow: onPastFirstRow,
            onExitTop: onExitTop,
            emptyMessage: emptyMessage,
            hearsPageButtons: hearsPageButtons,
            showsCardMenu: showsCardMenu,
            card: { entry, width, pixelWidth in
                LibraryCard(
                    entry: entry,
                    options: options,
                    width: width,
                    imageURL: options.layout == .grid
                        ? entry.flatMap { imageURL($0.item, options.shape, pixelWidth) }
                        : nil,
                    showsMenu: showsCardMenu,
                )
            },
            header: header,
        )
    }
}
