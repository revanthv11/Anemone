import AnemoneJellyfin
import SwiftUI

/// Sizes shared by item pages, matching the home page's where they overlap.
enum ItemLayout {
    static let horizontalInset: CGFloat = 80
    static let topInset: CGFloat = 60
    static let sectionSpacing: CGFloat = 16
    static let cardSpacing: CGFloat = 40
    /// Room above and below each row so the focus lift isn't clipped.
    static let focusPadding: CGFloat = 30
    /// Wholphin keeps header text to 60% of the screen.
    static let textWidth: CGFloat = 1100
    static let logoWidth: CGFloat = 640
    static let logoHeight: CGFloat = 120
    static let personWidth: CGFloat = 160
    /// Backdrops are faded and dimmed, so 1080p is plenty even on a 4K screen.
    static let backdropPixelWidth: CGFloat = 1920
    /// Scroll target for bringing a page's header back into view.
    static let headerID = "header"
}

/// What has focus on an item page.
enum ItemFocus: Hashable {
    case action(ItemAction)
    case overview
    case tab(MediaItem.ID)
    case card(row: String, item: String)

    /// Whether this is part of a page's header, which should scroll fully into view.
    var isInHeader: Bool {
        switch self {
        case .action, .overview, .tab: true
        case .card: false
        }
    }
}

enum ItemAction: Hashable {
    case play
    case restart
    case shuffle
    case played
    case favorite
    case trailer
    case delete
    case sort
    case filter
    case viewOptions
}

/// Each row's last-focused card, so coming back to a row lands where the user left it, as on
/// the home page (see docs/spikes/home-focus.md).
struct RowMemory {
    private var lastItemByRow: [String: String] = [:]

    mutating func note(_ focus: ItemFocus?) {
        if case let .card(row, item) = focus {
            lastItemByRow[row] = item
        }
    }

    /// Where focus lands on entering a row: its last-focused card, or `first`.
    func entry(row: String, first: String?) -> ItemFocus? {
        (lastItemByRow[row] ?? first).map { .card(row: row, item: $0) }
    }
}

extension View {
    /// Moves focus to `target` once, when the page first has it to offer. tvOS can leave focus
    /// in the sidebar while a page loads; after this, tvOS restores focus itself, including
    /// after Back.
    func initialFocus(_ focus: FocusState<ItemFocus?>.Binding, _ target: ItemFocus?) -> some View {
        modifier(InitialFocus(focus: focus, target: target))
    }
}

private struct InitialFocus: ViewModifier {
    let focus: FocusState<ItemFocus?>.Binding
    let target: ItemFocus?
    @State private var placed = false

    func body(content: Content) -> some View {
        content
            .defaultFocus(focus, target)
            .task(id: target) {
                guard !placed, let target else { return }
                placed = true
                focus.wrappedValue = target
            }
    }
}
