import Observation
import SwiftUI

/// What a card's long-press menu is about: the item the card shows, as the app knows it.
///
/// AnemoneUI doesn't know Jellyfin's types, so the item travels untyped, and the app's menu
/// reads it back. A caller passes whatever it has: an item whose watched and favourite state it
/// knows, or one whose state it doesn't, and the menu offers what it can for each.
public struct CardMenuItem: Hashable, Sendable {
    public let id: String
    public let value: any Hashable & Sendable

    public init<Item: Identifiable & Hashable & Sendable>(_ item: Item) where Item.ID == String {
        id = item.id
        value = item
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        AnyHashable(lhs.value) == AnyHashable(rhs.value)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(AnyHashable(value))
    }
}

/// What a card draws over its artwork that its menu can change: the favourite heart, the
/// watched check and the progress bar.
public struct CardMarks: Hashable, Sendable {
    public var badges: CardBadges
    /// From 0 to 1, as `MediaCard` takes it.
    public var progress: Double?

    public init(badges: CardBadges = CardBadges(), progress: Double? = nil) {
        self.badges = badges
        self.progress = progress
    }
}

/// The long-press menu on cards, ported from Wholphin's `ContextMenu`. The app injects one
/// through `cardMenu`, a `MediaCard` given a `CardMenuItem` says what it shows, and the button
/// holding the card opens the menu, so call sites don't build menus themselves.
public struct CardMenu {
    /// The menu's buttons for an item, given the marks the card's caller passed.
    let content: @MainActor (CardMenuItem, CardMarks) -> AnyView
    public let marks: CardMarksStore

    public init(
        marks: CardMarksStore,
        @ViewBuilder content: @escaping @MainActor (CardMenuItem, CardMarks) -> some View,
    ) {
        self.marks = marks
        self.content = { AnyView(content($0, $1)) }
    }
}

public extension EnvironmentValues {
    /// The app's card menu. `nil` leaves cards without one.
    @Entry var cardMenu: CardMenu?
}

public extension View {
    /// Opens the app's card menu on a long press of Select, for the `MediaCard` inside. Put it on
    /// the card's button or link: tvOS opens a context menu only on what has focus, so one inside
    /// the button's label never opens.
    func cardMenu() -> some View {
        modifier(CardMenuHost())
    }
}

/// What a `MediaCard` asks its button's menu for: its item, and the marks its caller passed.
struct CardMenuRequest: Equatable, Sendable {
    let item: CardMenuItem
    let marks: CardMarks
}

/// Carries a card's `CardMenuRequest` up from inside a button's label to the button.
struct CardMenuRequestKey: PreferenceKey {
    static var defaultValue: CardMenuRequest? {
        nil
    }

    static func reduce(value: inout CardMenuRequest?, nextValue: () -> CardMenuRequest?) {
        value = value ?? nextValue()
    }
}

private struct CardMenuHost: ViewModifier {
    @Environment(\.cardMenu) private var menu
    @State private var request: CardMenuRequest?

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(CardMenuRequestKey.self) { [$request] request in
                $request.wrappedValue = request
            }
            // Empty without a request or a menu, which shows no menu.
            .contextMenu {
                if let menu, let request {
                    menu.content(request.item, request.marks)
                }
            }
    }
}
