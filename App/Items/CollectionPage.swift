import AnemoneJellyfin
import AnemonePlayback
import AnemoneUI
import SwiftUI

/// Wholphin's collection page (`CollectionDetails`), with its default view options: the
/// collection's header and actions, then a row for each type of item in it. While a card has
/// focus, the header and backdrop describe that card instead, as in Wholphin, unless View's
/// "Show details" is off.
struct CollectionPage: View {
    @Binding var collection: ItemDetails

    @Environment(BrowseModel.self) private var browse
    @Environment(\.theme) private var theme
    @FocusState private var focus: ItemFocus?
    @State private var memory = RowMemory()
    /// In the order the sort asks for.
    @State private var items: [ItemDetails]?
    /// The sort and filter `items` were loaded with, so Play follows them only while they show.
    @State private var itemsQuery: CollectionDisplay.Query?
    @State private var problem: String?
    @State private var alert: ItemAlert?
    @State private var playback: PlaybackRequest?
    /// The card the header describes; `nil` for the collection itself.
    @State private var focusedEntry: ItemDetails?
    /// Follows `focusedEntry` after a pause, like the home page's backdrop.
    @State private var backdropEntry: ItemDetails?
    @State private var canDelete = false
    /// `nil` until read from storage.
    @State private var display: CollectionDisplay?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let focusedEntry {
                    EntryHeader(entry: focusedEntry)
                } else {
                    collectionHeader
                }
            }
            .foregroundStyle(theme.onBackground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Self.headerHeight, alignment: .bottomLeading)
            .padding(.horizontal, ItemLayout.horizontalInset)
            .padding(.top, ItemLayout.topInset)
            // The same gap as between an item page's header and its buttons.
            .padding(.bottom, ItemLayout.sectionSpacing)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: ItemLayout.sectionSpacing) {
                    buttons
                    rows
                }
                .padding(.horizontal, ItemLayout.horizontalInset)
                .padding(.bottom, ItemLayout.focusPadding)
            }
        }
        .background {
            BackdropImage(url: browse.imageURL(
                (backdropEntry ?? collection).item.backdropImage,
                width: ItemLayout.backdropPixelWidth,
            ))
            .ignoresSafeArea()
        }
        .initialFocus($focus, .action(.play))
        .itemAlert($alert)
        .player($playback) {
            await loadItems()
        }
        .onChange(of: focus) { _, focus in
            memory.note(focus)
            switch focus {
            case let .card(_, item)? where display?.showsDetails ?? true:
                focusedEntry = entry(item)
            case .some:
                focusedEntry = nil
            case nil:
                break
            }
        }
        .onChange(of: display?.showsDetails) { _, showsDetails in
            if showsDetails == false {
                focusedEntry = nil
            }
        }
        .task(id: focusedEntry?.id) {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            backdropEntry = focusedEntry
        }
        // Of the extras other pages load, this one shows only Delete. `/Items/{id}` brings
        // `CanDelete` with the collection; it's asked for only when the collection came without.
        .task(id: collection.id) {
            if let known = collection.canDelete {
                canDelete = known
                return
            }
            let session = browse.session
            let id = collection.id
            canDelete = await browse.optional(attempt { try await session.canDelete(id: id) }) ?? false
        }
        .collectionDisplay($display, for: collection.id)
        // Runs again when the sort or filter changes.
        .pageTask(id: display?.query) {
            await loadItems()
        }
        // Gone at once after Back from a deleted item, before the reload above lands.
        .onItemsDeleted { deleted in
            items?.removeAll { $0.item.wasDeleted(in: deleted) }
        }
    }

    private func loadItems() async {
        guard let query = display?.query else { return }
        do {
            items = try await browse.session.collectionItems(
                id: collection.id,
                sort: query.sort,
                filter: query.filter,
            )
            itemsQuery = query
            problem = nil
        } catch {
            // A failed refresh keeps the rows already showing.
            let message = browse.problem(with: error, failure: "Couldn't load what's in \(collection.item.name).")
            if items == nil {
                problem = message
            }
        }
    }

    /// In the order and with the filters the page shows, as Wholphin's Play All takes them, from
    /// the items it lists rather than asking for them again.
    private func play(shuffled: Bool) {
        let order = display.map { (sort: $0.sort, filter: $0.filter) }
        let shown = itemsQuery != nil && itemsQuery == display?.query ? items : nil
        Task {
            await browse.playQueue(of: collection, shuffled: shuffled, order: order, shown: shown) {
                playback = $0
            } failed: {
                alert = $0
            }
        }
    }

    /// Wholphin's `HeaderUtils.height`, with room for a logo.
    private static let headerHeight: CGFloat = 420

    /// Wholphin's `CollectionDetailsHeader`.
    private var collectionHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            ItemTitle(title: collection.item.name, logo: collection.logo)
            QuickDetails(details: collection)
            if !collection.genres.isEmpty {
                NameList(names: collection.genres)
            }
            if let tagline = collection.tagline {
                Text(tagline)
                    .font(.callout)
                    .italic()
            }
            if let overview = collection.item.overview {
                OverviewButton(title: collection.item.name, overview: overview)
                    .focused($focus, equals: .overview)
            }
        }
        .frame(maxWidth: ItemLayout.textWidth, alignment: .leading)
    }

    /// Wholphin's `CollectionButtons`.
    private var buttons: some View {
        HStack(spacing: 24) {
            ActionButton(title: String(localized: "Play"), systemImage: "play.fill") {
                play(shuffled: false)
            }
            .focused($focus, equals: .action(.play))
            .accessibilityIdentifier("action.play")
            ActionButton(title: String(localized: "Shuffle"), systemImage: "shuffle") {
                play(shuffled: true)
            }
            .focused($focus, equals: .action(.shuffle))
            .accessibilityIdentifier("action.shuffle")
            FavoriteButton(isFavorite: collection.userState.isFavorite) {
                Task { await setFavorite(!collection.userState.isFavorite) }
            }
            .focused($focus, equals: .action(.favorite))
            DeleteButton(item: collection, canDelete: canDelete).focused($focus, equals: .action(.delete))
            CollectionOptionsButtons(collection: collection, display: $display, focus: $focus)
        }
        .padding(.vertical, 20)
        .focusSection()
    }

    @ViewBuilder
    private var rows: some View {
        if let items, let display {
            let typeRows = display.separateTypes ? CollectionSection.sections(items) : nil
            // The rows leave out types without a row, so a collection of only those says this too.
            if typeRows?.isEmpty ?? items.isEmpty {
                Text(display.filter.isEmpty
                    ? "There's nothing in this collection yet."
                    : "Nothing in this collection matches the filters.")
                    .foregroundStyle(theme.secondaryText)
            }
            if let typeRows {
                ForEach(typeRows) { section in
                    ItemRow(
                        id: section.rowID,
                        title: section.title,
                        items: section.items,
                        focus: $focus,
                        memory: memory,
                    )
                }
            } else {
                CollectionGrid(items: items, options: display.gridOptions, focus: $focus)
            }
        } else if let problem {
            NoticeText(problem)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
        }
    }

    /// Each item shows once, in its row or in the grid.
    private func entry(_ item: String) -> ItemDetails? {
        items?.first { $0.id == item }
    }

    private func setFavorite(_ isFavorite: Bool) async {
        if let state = await browse.save(.favorite(isFavorite), for: collection, failed: { alert = $0 }) {
            collection.apply(state)
        }
    }
}

/// The focused card's details in place of the collection's, like the home page header.
private struct EntryHeader: View {
    let entry: ItemDetails

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(entry.cardTitle)
                .font(.title2.bold())
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            if entry.item.kind == .episode, let subtitle = entry.cardSubtitle {
                Text(subtitle)
                    .font(.title3)
                    .lineLimit(1)
            }
            QuickDetails(details: entry)
            Text(entry.item.overview ?? " ")
                .font(.callout)
                .lineLimit(3, reservesSpace: true)
                .frame(maxWidth: ItemLayout.textWidth, alignment: .leading)
        }
    }
}

private extension CollectionSection {
    var rowID: String {
        "\(kind)"
    }

    var title: String {
        switch kind {
        case .movie: String(localized: "Movies")
        case .series: String(localized: "TV Shows")
        case .episode: String(localized: "Episodes")
        case .video: String(localized: "Videos")
        case .collection: String(localized: "Collections")
        case .musicAlbum: String(localized: "Albums")
        case .musicVideo: String(localized: "Music Videos")
        default: String(localized: "Other")
        }
    }
}
