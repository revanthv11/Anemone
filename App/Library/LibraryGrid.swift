import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// A library's items as a grid that pages in ahead of focus, with Wholphin's alphabet bar,
/// position footer, Back to jump to the top, and paging with the remote's page buttons. The same
/// grid draws the list layouts, one title per row, and the Genres and Studios tabs.
///
/// One `LazyVGrid` in a vertical `ScrollView`, with no focus section of its own; see
/// docs/spikes/home-focus.md.
struct LibraryGrid<Header: View, Card: View>: View {
    let pager: LibraryPager
    let options: GridViewOptions
    /// Wholphin shows the alphabet bar only when the grid is sorted by name.
    let showsJumpBar: Bool
    /// Where a letter's items start in the grid.
    let position: (Character) async throws -> Int
    let onSelect: (MediaItem) -> Void
    let onFocus: (Int) -> Void
    /// Called as focus moves on from the first row (`true`) or back to it (`false`), so the
    /// page can tuck its tabs away as Wholphin does.
    let onPastFirstRow: (Bool) -> Void
    /// Shown under the header when the grid is empty.
    let emptyMessage: String
    /// Draws an entry, or its placeholder while its page loads, at a width in points and pixels.
    let card: (_ entry: LibraryEntry?, _ width: CGFloat, _ pixelWidth: Int) -> Card
    let header: Header

    @FocusState private var focusedIndex: Int?
    /// Where focus goes when it comes back to the grid, and what the footer counts.
    @State private var lastFocused = 0
    @State private var focusTracking = FocusTracking()
    @State private var scrollSize = CGSize.zero
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var measured = MeasuredLayout()

    init(
        pager: LibraryPager,
        options: GridViewOptions,
        showsJumpBar: Bool,
        position: @escaping (Character) async throws -> Int,
        onSelect: @escaping (MediaItem) -> Void,
        onFocus: @escaping (Int) -> Void = { _ in },
        onPastFirstRow: @escaping (Bool) -> Void = { _ in },
        emptyMessage: String = "Nothing to show.",
        @ViewBuilder card: @escaping (_ entry: LibraryEntry?, _ width: CGFloat, _ pixelWidth: Int) -> Card,
        @ViewBuilder header: () -> Header,
    ) {
        self.pager = pager
        self.options = options
        self.showsJumpBar = showsJumpBar
        self.position = position
        self.onSelect = onSelect
        self.onFocus = onFocus
        self.onPastFirstRow = onPastFirstRow
        self.emptyMessage = emptyMessage
        self.card = card
        self.header = header()
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: GridLayout.headerSpacing) {
                    header
                        .focusSection()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured.headerHeight = $0 }
                    if pager.count > 0 {
                        grid
                    } else {
                        Text(emptyMessage)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                    }
                }
                .padding(.leading, GridLayout.horizontalInset)
                .padding(.trailing, trailingInset)
                .padding(.vertical, GridLayout.focusPadding)
            }
            // A vertical scroll view is only as wide as its content unless told otherwise.
            .frame(maxWidth: .infinity)
            .scrollPosition($scrollPosition)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { scrollSize = $0 }
            if showsJumpBar {
                JumpBar(current: currentLetter) {
                    // Known for certain here, unlike moves to the header or the sidebar.
                    focusTracking.hasLeftGrid = true
                } onSelect: { letter in
                    jump(to: letter)
                }
                .padding(.trailing, GridLayout.jumpBarInset)
            }
        }
        .overlay(alignment: .bottom) {
            if pager.count > 0 {
                footer
            }
        }
        .background {
            RemotePageButtons { forward in
                page(forward: forward)
            }
        }
        .onExitCommand(perform: backToTop)
        .onChange(of: ObjectIdentifier(pager)) {
            // A new sort or filter starts again from the top.
            lastFocused = 0
            scrollPosition.scrollTo(edge: .top)
        }
        .onChange(of: focusedIndex) { _, index in
            guard let index else {
                // Focus also passes through nil between cards, so it has only left the grid if
                // the move that took it away was off an edge.
                focusTracking.hasLeftGrid = focusTracking.lastMoveLeavesGrid
                return
            }
            // Coming back from the header, the alphabet bar or the sidebar, the focus engine picks
            // the nearest card; Wholphin goes back to the one focused last. `focusSection` or
            // `defaultFocus` on the grid would do that, but on a lazy grid either one makes every
            // focus move take seconds while accessibility is on (docs/spikes/home-focus.md).
            let returning = focusTracking.hasLeftGrid
            focusTracking.hasLeftGrid = false
            let remembered = lastFocused
            lastFocused = index
            onFocus(index)
            onPastFirstRow(index >= options.columnCount)
            // If the card can't take focus after all, focus stays here and is counted here.
            if returning, index != remembered, isOnScreen(remembered, near: index) {
                focusedIndex = remembered
            }
        }
    }

    /// Whether the card at `index` is likely on screen along with `other`: within as many rows
    /// as fit in the grid's height.
    private func isOnScreen(_ index: Int, near other: Int) -> Bool {
        let cardWidth = options.cardWidth(in: scrollSize.width - GridLayout.horizontalInset - trailingInset)
        // The measured card includes its caption; before any card is measured, the artwork alone.
        let cardHeight = measured.cardHeight > 0 ? measured.cardHeight : cardWidth / options.shape.aspectRatio
        let rows = max(Int(scrollSize.height / (cardHeight + options.itemSpacing)), 1)
        return abs(index / options.columnCount - other / options.columnCount) < rows
    }

    private var grid: some View {
        let cardWidth = options.cardWidth(in: scrollSize.width - GridLayout.horizontalInset - trailingInset)
        let columns = Array(
            repeating: GridItem(.fixed(cardWidth), spacing: options.itemSpacing, alignment: .top),
            count: options.columnCount,
        )
        return LazyVGrid(columns: columns, alignment: .leading, spacing: options.itemSpacing) {
            // No cards until the width is known, so none are laid out (and fetch artwork) at 1 pt.
            ForEach(0 ..< (scrollSize.width > 0 ? pager.count : 0), id: \.self) { index in
                GridCell(
                    index: index,
                    pager: pager,
                    isListRow: options.layout != .grid,
                    width: cardWidth,
                    card: card,
                    onSelect: onSelect,
                )
                .focused($focusedIndex, equals: index)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured.cardHeight = $0 }
            }
        }
        .onMoveCommand { direction in
            // Called for every press while a card has focus, whether or not focus moves.
            let column = lastFocused % options.columnCount
            focusTracking.lastMoveLeavesGrid = switch direction {
            case .left: column == 0
            case .right: column == options.columnCount - 1 || lastFocused == pager.count - 1
            case .up: lastFocused < options.columnCount
            default: false
            }
        }
    }

    private var trailingInset: CGFloat {
        showsJumpBar ? GridLayout.jumpBarSpacing : GridLayout.horizontalInset
    }

    private var footer: some View {
        Text("\(lastFocused + 1) / \(pager.count)")
            .font(.caption)
            .monospacedDigit()
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(.black.opacity(0.5), in: .capsule)
            .accessibilityIdentifier("grid.position")
    }

    /// The letter of the item focus is on (or last was), as Wholphin highlights it.
    private var currentLetter: Character {
        LibraryJump.letter(for: pager.item(at: lastFocused)?.sortName) ?? LibraryJump.letters[0]
    }

    /// Scrolls to the letter's first item and focuses it, as Wholphin's alphabet bar does.
    private func jump(to letter: Character) {
        Task {
            guard let index = try? await position(letter), index < pager.count else { return }
            await jump(toIndex: index)
        }
    }

    /// Wholphin's paging with the remote: six rows down or up from the focused card, or more in
    /// a big library. Only while a card has focus, as Wholphin hears the keys only in its grid.
    private func page(forward: Bool) {
        guard focusedIndex != nil else { return }
        let index = LibraryJump.page(
            from: lastFocused,
            forward: forward,
            columns: options.columnCount,
            count: pager.count,
        )
        guard index != lastFocused else { return }
        Task {
            await jump(toIndex: index)
        }
    }

    /// Loads the item's page, scrolls to its row and focuses it.
    private func jump(toIndex index: Int) async {
        _ = try? await pager.load(at: index)
        // Worked out rather than `scrollTo(id:)`, which also nudges the grid sideways.
        let row = CGFloat(index / options.columnCount)
        let gridTop = GridLayout.focusPadding + measured.headerHeight + GridLayout.headerSpacing
        scrollPosition.scrollTo(y: gridTop + row * (measured.cardHeight + options.itemSpacing))
        lastFocused = index
        focusedIndex = index
    }

    /// Wholphin's Back behaviour: from anywhere but the first card, Back returns to the top; from
    /// there, it does what it normally does (opens the sidebar).
    private var backToTop: (() -> Void)? {
        guard let focusedIndex, focusedIndex > 0 else { return nil }
        let isNear = focusedIndex < options.columnCount * 6
        return {
            withAnimation(isNear ? .default : nil) {
                scrollPosition.scrollTo(edge: .top)
            }
            self.focusedIndex = 0
        }
    }
}

/// Sizes the jump works from. Every card in a grid has the same height.
private final class MeasuredLayout {
    var headerHeight: CGFloat = 0
    var cardHeight: CGFloat = 0
}

/// Kept outside SwiftUI's state, so updating it doesn't redraw the grid.
private final class FocusTracking {
    /// The last arrow press was off the grid's edge: towards the header, the alphabet bar or
    /// the sidebar.
    var lastMoveLeavesGrid = false
    /// Focus went off the grid that way and hasn't come back yet.
    var hasLeftGrid = false
}

/// One card. Kept separate so a page arriving redraws only the cards on screen, not the grid.
private struct GridCell<Card: View>: View {
    let index: Int
    let pager: LibraryPager
    /// List rows show focus as a highlight; cards lift their artwork, which needs a borderless
    /// button.
    let isListRow: Bool
    let width: CGFloat
    let card: (LibraryEntry?, CGFloat, Int) -> Card
    let onSelect: (MediaItem) -> Void

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let entry = pager.item(at: index)
        let button = Button {
            if let item = entry?.item {
                onSelect(item)
            }
        } label: {
            card(entry, width, Int(width * displayScale))
        }
        Group {
            if isListRow {
                button.buttonStyle(ListRowButtonStyle())
            } else {
                button.buttonStyle(.borderless)
            }
        }
        .accessibilityLabel(entry?.item.displayTitle ?? "Loading")
        .accessibilityIdentifier("grid.card.\(index)")
        .task {
            await pager.prefetch(around: index)
        }
    }
}

/// Wholphin's alphabet bar: a column of letters down the right edge. Entering it focuses the
/// current letter.
private struct JumpBar: View {
    let current: Character
    let onFocus: () -> Void
    let onSelect: (Character) -> Void

    @FocusState private var focusedLetter: Character?

    var body: some View {
        VStack(spacing: 2) {
            ForEach(LibraryJump.letters, id: \.self) { letter in
                Button {
                    onSelect(letter)
                } label: {
                    Text(String(letter))
                }
                .buttonStyle(LetterButtonStyle(isCurrent: letter == current))
                .focused($focusedLetter, equals: letter)
                .accessibilityIdentifier("grid.letter.\(letter)")
            }
        }
        .focusSection()
        .defaultFocus($focusedLetter, current, priority: .userInitiated)
        .onChange(of: focusedLetter) { _, letter in
            if letter != nil {
                onFocus()
            }
        }
    }
}

private struct LetterButtonStyle: ButtonStyle {
    let isCurrent: Bool

    func makeBody(configuration: Configuration) -> some View {
        LetterLabel(label: configuration.label, isCurrent: isCurrent, isPressed: configuration.isPressed)
    }
}

private struct LetterLabel: View {
    let label: ButtonStyleConfiguration.Label
    let isCurrent: Bool
    let isPressed: Bool

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        label
            .font(.system(size: 20, weight: isCurrent ? .bold : .medium))
            .foregroundStyle(foreground)
            .frame(width: GridLayout.letterSize, height: GridLayout.letterSize)
            .background {
                Circle()
                    .fill(isFocused ? AnyShapeStyle(.white) : AnyShapeStyle(.clear))
            }
            .scaleEffect(isFocused ? (isPressed ? 1.1 : 1.3) : 1)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }

    private var foreground: AnyShapeStyle {
        if isFocused {
            AnyShapeStyle(.black)
        } else if isCurrent {
            AnyShapeStyle(.tint)
        } else {
            AnyShapeStyle(.secondary)
        }
    }
}

enum GridLayout {
    static let horizontalInset: CGFloat = 80
    static let headerSpacing: CGFloat = 40
    /// Room around the grid so the focus lift isn't clipped.
    static let focusPadding: CGFloat = 30
    /// Between the grid and the alphabet bar.
    static let jumpBarSpacing: CGFloat = 40
    static let jumpBarInset: CGFloat = 30
    static let letterSize: CGFloat = 32
}
