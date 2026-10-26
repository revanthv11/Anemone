import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// Wholphin's default home page: a header for the focused item over its backdrop, then rows.
struct HomeView: View {
    @Environment(BrowseModel.self) private var browse
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var stack = PageStack()

    var body: some View {
        NavigationStack(path: $stack.path) {
            content
                .itemPages(in: stack)
        }
        .task(id: stack.path.isEmpty && scenePhase == .active) {
            // Refreshes the rows when Home shows again, after Back from the pages pushed here and
            // when the app returns to the foreground, like Wholphin's refresh on resume. Watching
            // the path because tvOS doesn't restart the root page's tasks when a page is popped.
            // Opening a page or leaving the app cancels a refresh still under way.
            guard stack.path.isEmpty, scenePhase == .active else { return }
            await browse.refresh()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch browse.home {
        case .loading:
            ProgressView()
        case let .loaded(home) where !home.rows.isEmpty:
            HomeRows(content: home)
        case let .loaded(home) where home.failedRows.isEmpty:
            HomeMessage(
                title: "Nothing to show yet",
                message: "Add media to your libraries in Jellyfin, or ask the server's admin for access to them.",
            )
        case .loaded, .failed:
            HomeMessage(
                title: "Couldn't load your home page",
                message: "Check that \(browse.server.name) is running, then try again.",
            ) {
                Button("Try again") {
                    Task { await browse.load() }
                }
            }
        case .signedOut:
            HomeMessage(
                title: "Signed out",
                message: "\(browse.server.name) signed you out. Sign in again to continue.",
            ) {
                Button("Sign in again") {
                    model.signOut()
                }
            }
        }
    }
}

/// The header, backdrop and rows.
///
/// Rows sit in a plain `VStack`, so none is discarded while scrolled away, and each remembers
/// its last-focused card through `defaultFocus`; see docs/spikes/home-focus.md. A refresh swaps
/// in new rows under the same view, so that memory and the header stay.
private struct HomeRows: View {
    let content: HomeContent

    @Environment(BrowseModel.self) private var browse
    @FocusState private var focusedCard: CardID?
    @State private var lastFocusedByRow: [HomeRow.ID: CardID] = [:]
    @State private var headerItem: MediaItem?
    @State private var backdropItem: MediaItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HomeHeader(item: headerItem ?? firstItem)
                .padding(.horizontal, HomeLayout.horizontalInset)
                .padding(.bottom, HomeLayout.headerSpacing)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: HomeLayout.rowSpacing) {
                    ForEach(content.rows) { row in
                        HomeRowView(row: row, focusedCard: $focusedCard)
                            .defaultFocus($focusedCard, rememberedCard(in: row), priority: .userInitiated)
                    }
                    if !content.failedRows.isEmpty {
                        NoticeText("Some rows couldn't be loaded.")
                    }
                }
                .padding(.horizontal, HomeLayout.horizontalInset)
                .padding(.bottom, HomeLayout.focusPadding)
            }
        }
        .background {
            BackdropImage(url: backdropURL)
                .ignoresSafeArea()
        }
        .task {
            // tvOS puts focus in the sidebar while the page loads, so move it to the first row,
            // as Wholphin does. Only the first time rows appear for this profile; after that,
            // focus stays wherever the user put it.
            guard let first = content.rows.first, browse.claimInitialFocus() else { return }
            focusedCard = rememberedCard(in: first)
        }
        .onChange(of: content) { old, new in
            keepFocus(from: old, to: new)
        }
        .onChange(of: focusedCard) { _, card in
            guard let card, let item = item(for: card) else { return }
            lastFocusedByRow[card.rowID] = card
            headerItem = item
        }
        .task(id: focusedCard) {
            // Debounced like Wholphin's backdrop, so moving along a row doesn't load every image.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let focusedCard, let item = item(for: focusedCard) else { return }
            backdropItem = item
        }
    }

    private var firstItem: MediaItem? {
        content.rows.first?.items.first
    }

    private var backdropURL: URL? {
        browse.imageURL((backdropItem ?? firstItem)?.backdropImage, width: HomeLayout.backdropPixelWidth)
    }

    /// Where focus lands on entering a row: the card last focused there, or its first card.
    private func rememberedCard(in row: HomeRow) -> CardID? {
        lastFocusedByRow[row.id] ?? row.firstCard
    }

    private func item(for card: CardID) -> MediaItem? {
        content.item(for: card)
    }

    /// After a refresh, forgets remembered cards whose items left their rows, so those rows start
    /// from their first card again. If the focused card went, focus moves to its row's first card,
    /// or to the next row when that row went too, instead of falling back to the sidebar.
    private func keepFocus(from old: HomeContent, to new: HomeContent) {
        let remembered = lastFocusedByRow.filter { new.item(for: $0.value) != nil }
        lastFocusedByRow = remembered
        guard let card = focusedCard, new.item(for: card) == nil,
              let row = new.nearestRow(to: card.rowID, in: old)
        else { return }
        focusedCard = remembered[row.id] ?? row.firstCard
    }
}

/// A card's focus identity. The same item can appear in more than one row.
private struct CardID: Hashable {
    let rowID: HomeRow.ID
    let itemID: MediaItem.ID
}

private extension HomeContent {
    func item(for card: CardID) -> MediaItem? {
        rows.first { $0.id == card.rowID }?.items.first { $0.id == card.itemID }
    }

    /// The row with the given ID, or when it's gone, the first row after it in `old` that's still
    /// here, else the nearest one before it.
    func nearestRow(to id: HomeRow.ID, in old: HomeContent) -> HomeRow? {
        let oldIDs = old.rows.map(\.id)
        let index = oldIDs.firstIndex(of: id) ?? 0
        let candidates = oldIDs[index...] + oldIDs[..<index].reversed()
        return candidates.lazy.compactMap { id in rows.first { $0.id == id } }.first ?? rows.first
    }
}

private extension HomeRow {
    var firstCard: CardID? {
        items.first.map { CardID(rowID: id, itemID: $0.id) }
    }
}

private struct HomeHeader: View {
    let item: MediaItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item?.displayTitle ?? " ")
                .font(.title2.bold())
                .lineLimit(1)
                .accessibilityIdentifier("home.header.title")
            Text(item?.subtitle ?? " ")
                .font(.title3)
                .lineLimit(1)
            Text(item?.details ?? " ")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(item?.overview ?? " ")
                .font(.callout)
                .lineLimit(3, reservesSpace: true)
                .frame(maxWidth: 1100, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: HomeLayout.headerHeight, alignment: .bottomLeading)
        .animation(nil, value: item)
    }
}

private struct HomeRowView: View {
    let row: HomeRow
    let focusedCard: FocusState<CardID?>.Binding

    @Environment(BrowseModel.self) private var browse
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(row.title)
                .font(.headline)
            ScrollView(.horizontal) {
                LazyHStack(spacing: HomeLayout.cardSpacing) {
                    ForEach(row.items) { item in
                        NavigationLink(value: item) {
                            MediaCard(
                                title: item.displayTitle,
                                subtitle: item.subtitle ?? item.year.map(String.init),
                                imageURL: imageURL(for: item),
                                shape: row.shape,
                                width: row.shape.cardWidth,
                                progress: item.progress,
                            )
                        }
                        .buttonStyle(.borderless)
                        .focused(focusedCard, equals: CardID(rowID: row.id, itemID: item.id))
                        .accessibilityIdentifier("card.\(row.id).\(item.id)")
                    }
                }
                .padding(.vertical, HomeLayout.focusPadding)
            }
            .scrollClipDisabled()
        }
        .focusSection()
    }

    private func imageURL(for item: MediaItem) -> URL? {
        browse.imageURL(item.image(for: row.shape), width: row.shape.cardWidth * displayScale)
    }
}

private struct HomeMessage<Actions: View>: View {
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 24) {
            Text(title)
                .font(.title2.bold())
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 1000)
            actions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension HomeMessage where Actions == EmptyView {
    init(title: String, message: String) {
        self.init(title: title, message: message) { EmptyView() }
    }
}

private enum HomeLayout {
    static let headerHeight: CGFloat = 340
    static let headerSpacing: CGFloat = 24
    static let horizontalInset: CGFloat = 80
    static let rowSpacing: CGFloat = 16
    static let cardSpacing: CGFloat = 40
    /// Room above and below each row so the focus lift isn't clipped.
    static let focusPadding: CGFloat = 30
    /// Backdrops are faded and dimmed, so 1080p is plenty even on a 4K screen.
    static let backdropPixelWidth: CGFloat = 1920
}

private extension HomeRow {
    var title: String {
        switch kind {
        case .continueWatching: "Continue Watching"
        case .nextUp: "Next Up"
        case let .recentlyAdded(library): "Recently Added in \(library.name)"
        }
    }

    /// Wholphin's default row styles: thumbs for watching rows, and per library type otherwise.
    var shape: CardShape {
        switch kind {
        case .continueWatching, .nextUp:
            .thumb
        case let .recentlyAdded(library):
            switch library.kind {
            case .music: .square
            case .photos, .homeVideos, .musicVideos: .thumb
            default: .poster
            }
        }
    }
}

extension CardShape {
    var cardWidth: CGFloat {
        switch self {
        case .poster: 200
        case .thumb: 340
        case .square: 240
        }
    }
}

extension MediaItem {
    func image(for shape: CardShape) -> ItemImage? {
        switch shape {
        case .poster: posterImage
        case .thumb: thumbImage
        case .square: squareImage
        }
    }

    /// The episode ("S1:E3 · Pilot") or season shown under the series name.
    var subtitle: String? {
        switch kind {
        case .episode:
            [episodeLabel, name].compactMap(\.self).joined(separator: " · ")
        case .season:
            name
        default:
            nil
        }
    }

    /// Year, running time and age rating, such as "2024 · 1h 52m · PG-13".
    var details: String {
        [
            year.map(String.init),
            runtime.map { $0.formatted(.units(allowed: [.hours, .minutes], width: .narrow)) },
            officialRating,
        ]
        .compactMap(\.self)
        .joined(separator: " · ")
    }
}
