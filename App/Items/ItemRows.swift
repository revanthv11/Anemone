import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// A row of cards that scrolls sideways, like a home row: its own focus section, entered at the
/// card last focused in it. VoiceOver reads its title as focus moves into it.
struct CardRow<Element: Identifiable, Card: View>: View where Element.ID == String {
    let id: String
    let title: String?
    /// What VoiceOver calls a row that shows no title, such as a season's episodes.
    var spokenTitle: String?
    let elements: [Element]
    let focus: FocusState<ItemFocus?>.Binding
    let memory: RowMemory
    /// The card scrolled to the row's leading edge. Cards are created lazily, so one far along
    /// the row has to be scrolled to before it can take focus.
    var scrollPosition: Binding<String?>?
    @ViewBuilder let card: (Element) -> Card

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(theme.onBackground)
                    .accessibilityAddTraits(.isHeader)
            }
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: ItemLayout.cardSpacing) {
                    ForEach(elements) { element in
                        card(element)
                            .cardMenu()
                            .focused(focus, equals: .card(row: id, item: element.id))
                            .accessibilityIdentifier("card.\(id).\(element.id)")
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, ItemLayout.focusPadding)
            }
            .scrollPosition(scrollPosition)
            .scrollClipDisabled()
        }
        .accessibilityRow(title ?? spokenTitle ?? "")
        .focusSection()
        .defaultFocus(focus, memory.entry(row: id, first: elements.first?.id), priority: .userInitiated)
    }
}

private extension View {
    @ViewBuilder
    func scrollPosition(_ position: Binding<String?>?) -> some View {
        if let position {
            scrollPosition(id: position, anchor: .leading)
        } else {
            self
        }
    }
}

/// A row of items that open their own pages.
struct ItemRow: View {
    let id: String
    let title: String
    let items: [ItemDetails]
    /// Every card's shape; `nil` picks one per item, as Wholphin's collection rows do.
    var shape: CardShape?
    let focus: FocusState<ItemFocus?>.Binding
    let memory: RowMemory

    var body: some View {
        CardRow(id: id, title: title, elements: items, focus: focus, memory: memory) { details in
            NavigationLink(value: details.item) {
                ItemCard(details: details, shape: shape ?? details.rowShape)
            }
            .buttonStyle(.borderless)
        }
    }
}

/// A card for an item on an item page, with Wholphin's watched and favourite marks. VoiceOver
/// reads its title and subtitle, an episode's in words, then its marks.
struct ItemCard: View {
    let details: ItemDetails
    let shape: CardShape
    var title: String?
    var subtitle: String?

    @Environment(BrowseModel.self) private var browse
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        MediaCard(
            title: title ?? details.cardTitle,
            subtitle: subtitle ?? details.cardSubtitle,
            imageURL: browse.imageURL(details.cardImage(for: shape), width: shape.cardWidth * displayScale),
            shape: shape,
            width: shape.cardWidth,
            progress: details.item.progress,
            badges: details.badges,
            menuItem: CardMenuItem(details),
        )
        // One element, so the card's button reads this once. With any marks a card menu has
        // changed since, as the card shows them.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(details.cardLabel(
            title: title,
            subtitle: subtitle,
            marks: browse.cardMarks.marks(for: details.id, given: details.cardMarks),
        ))
    }
}

/// Cast and crew, each opening their person page.
struct PeopleRow: View {
    let id: String
    let title: String
    let people: [Credit]
    let focus: FocusState<ItemFocus?>.Binding
    let memory: RowMemory

    @Environment(BrowseModel.self) private var browse
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        CardRow(id: id, title: title, elements: people, focus: focus, memory: memory) { credit in
            NavigationLink(value: credit.person) {
                PersonCard(
                    name: credit.name,
                    role: credit.role,
                    imageURL: browse.imageURL(credit.image, width: ItemLayout.personWidth * displayScale),
                    width: ItemLayout.personWidth,
                )
            }
            .buttonStyle(.personCard)
        }
    }
}
