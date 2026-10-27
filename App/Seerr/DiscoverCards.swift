#if ANEMONE_SEERR
    import AnemoneJellyfin
    import AnemoneSeerr
    import AnemoneUI
    import SwiftUI

    /// A card for a title found through Seerr, with its year and how much of it the server has.
    struct DiscoverCard: View {
        let item: DiscoverItem
        /// In place of the year and availability, such as a request's status.
        var subtitle: String?

        var body: some View {
            MediaCard(
                title: item.title,
                subtitle: subtitle ?? item.cardSubtitle,
                imageURL: item.posterURL,
                shape: .poster,
                width: CardShape.poster.cardWidth,
            )
        }
    }

    /// Opens a title from a Discover card: its page on the Jellyfin server once it's there, as
    /// Wholphin's `DiscoverItem.destination`, otherwise its Seerr page.
    struct DiscoverLink<Label: View>: View {
        let item: DiscoverItem
        @ViewBuilder let label: () -> Label

        var body: some View {
            if let jellyfinItem = item.jellyfinItem {
                NavigationLink(value: jellyfinItem, label: label)
            } else {
                NavigationLink(value: item, label: label)
            }
        }
    }

    /// A row of Discover cards, like a row of items on an item page.
    struct DiscoverItemsRow: View {
        let id: String
        let title: String
        let items: [DiscoverItem]
        let focus: FocusState<ItemFocus?>.Binding
        let memory: RowMemory

        var body: some View {
            CardRow(id: id, title: title, elements: items, focus: focus, memory: memory) { item in
                DiscoverLink(item: item) {
                    DiscoverCard(item: item)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(item.cardLabel())
            }
        }
    }

    /// A grid of Discover cards, for the Requests and search pages.
    struct DiscoverGrid: View {
        struct Entry: Identifiable {
            let id: String
            let item: DiscoverItem
            var subtitle: String?
        }

        let entries: [Entry]
        let focus: FocusState<ItemFocus?>.Binding

        var body: some View {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(
                        .fixed(CardShape.poster.cardWidth),
                        spacing: ItemLayout.cardSpacing,
                        alignment: .top,
                    ),
                    count: 6,
                ),
                alignment: .leading,
                spacing: ItemLayout.cardSpacing,
            ) {
                ForEach(entries) { entry in
                    DiscoverLink(item: entry.item) {
                        DiscoverCard(item: entry.item, subtitle: entry.subtitle)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(entry.item.cardLabel(subtitle: entry.subtitle))
                    .focused(focus, equals: .card(row: "grid", item: entry.id))
                    .accessibilityIdentifier("card.grid.\(entry.id)")
                }
            }
            .padding(.vertical, ItemLayout.focusPadding)
        }
    }

    extension View {
        /// Opens Seerr's title pages pushed on `stack`, as `itemPages(in:)` opens Jellyfin's and,
        /// through `seerrPages(in:)`, adds this.
        func discoverPages(in stack: PageStack?) -> some View {
            navigationDestination(for: DiscoverItem.self) { item in
                DiscoverItemPage(item: item)
                    .environment(\.pageStack, stack)
            }
        }
    }

    extension DiscoverItem {
        /// The Jellyfin item to open in its place, when the server has it.
        var jellyfinItem: MediaItem? {
            guard let jellyfinItemID, kind != .person else { return nil }
            return MediaItem(id: jellyfinItemID, name: title, kind: kind == .movie ? .movie : .series)
        }

        var cardSubtitle: String {
            [year.map(String.init), availability.label].compactMap(\.self).joined(separator: " · ")
        }

        /// What VoiceOver reads for its card: the title, then the year and availability, or the
        /// card's own subtitle, with pauses where the card has dots.
        func cardLabel(subtitle: String? = nil) -> String {
            let details = subtitle.map { [$0] } ?? [year.map(String.init), availability.label].compactMap(\.self)
            return ([title] + details).joined(separator: ", ")
        }
    }

    extension SeerrAvailability {
        /// What a card or page says of it; nothing when nothing's known.
        var label: String? {
            switch self {
            case .unknown: nil
            case .pending: "Requested"
            case .processing: "Processing"
            case .partiallyAvailable: "Partly available"
            case .available: "Available"
            case .blocklisted: "Blocklisted"
            case .deleted: "Deleted"
            }
        }
    }

    extension SeerrRequestStatus {
        var label: String {
            switch self {
            case .unknown: "Requested"
            case .pending: "Waiting for approval"
            case .approved: "Approved"
            case .declined: "Declined"
            case .failed: "Failed"
            case .completed: "Completed"
            }
        }
    }
#endif
