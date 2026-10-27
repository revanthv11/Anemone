import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// Cards for a library's titles: posters, thumbs or squares in the grid, or rows in a list.
struct LibraryCard: View {
    let entry: LibraryEntry?
    let options: GridViewOptions
    let width: CGFloat
    let imageURL: URL?

    var body: some View {
        let item = entry?.item
        switch options.layout {
        case .grid:
            MediaCard(
                title: item?.displayTitle ?? " ",
                subtitle: item.flatMap { $0.subtitle ?? $0.year.map(String.init) },
                imageURL: imageURL,
                shape: options.shape,
                width: width,
                progress: item?.progress,
                badges: entry?.details?.badges ?? CardBadges(),
                showsCaption: options.showTitles,
            )
        case .list, .denseList:
            LibraryListRow(entry: entry, isDense: options.layout == .denseList)
                .frame(width: width)
        }
    }
}

extension LibraryGrid where Card == LibraryCard {
    /// A grid of a library's titles, drawn as `options` says.
    init(
        pager: LibraryPager,
        options: GridViewOptions,
        showsJumpBar: Bool,
        position: @escaping (Character) async throws -> Int,
        imageURL: @escaping (_ item: MediaItem, _ shape: CardShape, _ pixelWidth: Int) -> URL?,
        onSelect: @escaping (MediaItem) -> Void,
        onFocus: @escaping (Int) -> Void = { _ in },
        onPastFirstRow: @escaping (Bool) -> Void = { _ in },
        emptyMessage: String = "Nothing to show.",
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
            emptyMessage: emptyMessage,
            card: { entry, width, pixelWidth in
                LibraryCard(
                    entry: entry,
                    options: options,
                    width: width,
                    imageURL: options.layout == .grid
                        ? entry.flatMap { imageURL($0.item, options.shape, pixelWidth) }
                        : nil,
                )
            },
            header: header,
        )
    }
}
