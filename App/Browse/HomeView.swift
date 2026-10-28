import AnemoneCore
import AnemoneJellyfin
import AnemoneUI
import SwiftUI
import UIKit

/// Wholphin's home page: a header for the focused item over its backdrop, then the rows chosen
/// in Settings › Home.
struct HomeView: View {
    /// Whether Home is the page chosen in the sidebar.
    let isSelected: Bool

    @Environment(BrowseModel.self) private var browse
    @Environment(AppModel.self) private var model
    @State private var stack = PageStack()

    var body: some View {
        NavigationStack(path: $stack.path) {
            content
                .pageTask(id: isSelected) {
                    // Refreshes the rows whenever Home shows again: after Back from the pages
                    // pushed here, on coming back to it in the sidebar, and when the app returns to
                    // the foreground. Leaving Home cancels a refresh still under way.
                    guard isSelected else { return }
                    await browse.refresh()
                }
                // Home is the stack's root, which `itemPages(in:)` doesn't reach.
                .environment(\.pageStack, stack)
                .itemPages(in: stack)
                .deepLinkPages(in: stack)
                .navigationDestination(for: HomeItemsLink.self) { link in
                    HomeItemsPage(link: link)
                        .environment(\.pageStack, stack)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch browse.home {
        case .loading:
            ProgressView()
        case let .loaded(home) where !home.rows.isEmpty:
            HomeRows(content: home, isCovered: !stack.path.isEmpty)
        case let .loaded(home) where home.failedRows.isEmpty:
            HomeMessage(
                title: String(localized: "Nothing to show yet"),
                message: String(
                    localized: "Add media to your libraries in Jellyfin, or ask the server's admin for access to them.",
                ),
            )
        case .loaded, .failed:
            HomeMessage(
                title: String(localized: "Couldn't load your home page"),
                message: String(localized: "Check that \(browse.server.name) is running, then try again."),
            ) {
                Button("Try again") {
                    Task { await browse.load() }
                }
            }
        case .signedOut:
            HomeMessage(
                title: String(localized: "Signed out"),
                message: String(localized: "\(browse.server.name) signed you out. Sign in again to continue."),
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
    /// Whether a page is pushed over Home.
    let isCovered: Bool

    @Environment(BrowseModel.self) private var browse
    @FocusState private var focusedCard: CardID?
    @State private var lastFocusedCard: CardID?
    @State private var lastFocusedByRow: [HomeRow.ID: CardID] = [:]
    /// Where focus belongs once Back from a page pushed over Home ends: the card that opened it,
    /// or its stand-in if a refresh removed it first.
    @State private var returningCard: CardID?
    /// A card for its row to scroll to, so that it exists before focus moves to it.
    @State private var scrollTarget: CardID?
    /// The card focus last left for something outside the rows: its long-press menu, the
    /// sidebar or a page.
    @State private var cardLeft: CardID?
    /// The stand-in for a card a refresh removed while focus was outside the rows, which focus
    /// goes to if nothing has it once a menu closes.
    @State private var orphanedFocus: CardID?
    /// `cardLeft`, kept for the scene: Home is built afresh when its tab is chosen again, as when
    /// a link opens a page on it from another tab, and Back from that page should still return
    /// to the card focused before.
    @SceneStorage("home.cardLeft.row") private var savedRow = ""
    @SceneStorage("home.cardLeft.item") private var savedItem = ""
    @State private var headerItem: MediaItem?
    @State private var backdropItem: MediaItem?
    /// The rows' scroll view and last row, so the last row can be scrolled to the top too.
    @State private var viewportHeight: CGFloat = 0
    @State private var lastRowHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HomeHeader(item: headerItem ?? firstItem)
                .padding(.horizontal, HomeLayout.horizontalInset)
                .padding(.bottom, HomeLayout.headerSpacing)
            ScrollViewReader { scroller in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: HomeLayout.rowSpacing) {
                        ForEach(content.rows) { row in
                            HomeRowView(row: row, focusedCard: $focusedCard, scrollTarget: scrollTarget)
                                .defaultFocus($focusedCard, rememberedCard(in: row), priority: .userInitiated)
                                .id(row.id)
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                                    if row.id == content.rows.last?.id {
                                        lastRowHeight = height
                                    }
                                }
                        }
                        if !content.failedRows.isEmpty {
                            NoticeText(String(localized: "Some rows couldn't be loaded."))
                        }
                    }
                    .padding(.horizontal, HomeLayout.horizontalInset)
                    // Enough below the last row for it to reach the top of the view too.
                    .padding(.bottom, max(HomeLayout.focusPadding, viewportHeight - lastRowHeight))
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
                .onChange(of: focusedCard) { _, card in
                    // The focused row's title goes to the top, under the header. Left to tvOS,
                    // the row lands anywhere that shows the card, and the bottom of the row
                    // above it then shows cut off under the header's overview.
                    guard let card else { return }
                    withAnimation { scroller.scrollTo(card.rowID, anchor: .top) }
                }
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
        .onChange(of: isCovered) { _, isCovered in
            if isCovered {
                let saved = savedItem.isEmpty ? nil : CardID(rowID: savedRow, itemID: savedItem)
                returningCard = focusedCard ?? lastFocusedCard ?? saved
            }
        }
        .onChange(of: content) { old, new in
            keepFocus(from: old, to: new)
        }
        .onChange(of: focusedCard) { old, card in
            guard let card else {
                cardLeft = old
                if let old {
                    (savedRow, savedItem) = (old.rowID, old.itemID)
                }
                return
            }
            cardLeft = nil
            orphanedFocus = nil
            guard let item = item(for: card) else { return }
            if let returningCard, returningCard != card, self.item(for: returningCard) != nil {
                // tvOS picked another card on coming back, because a refresh removed the one it
                // meant to focus. Moved once, like the library grid's return to its last card.
                self.returningCard = nil
                focusedCard = returningCard
                return
            }
            lastFocusedCard = card
            lastFocusedByRow[card.rowID] = card
            returningCard = nil
            scrollTarget = nil
            headerItem = item
        }
        .task(id: focusedCard) {
            // Debounced like Wholphin's backdrop, so moving along a row doesn't load every image.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let focusedCard, let item = item(for: focusedCard) else { return }
            backdropItem = item
        }
        .task(id: orphanedFocus) {
            // A card's menu removed it from its row, say with Remove from Next Up, and the refresh
            // landed before the menu closed: tvOS has nowhere to put focus then. Once nothing has
            // focus, it goes to the stand-in; focus elsewhere, such as in the sidebar, stays put.
            guard let target = orphanedFocus else { return }
            for _ in 0 ..< 12 {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, focusedCard == nil, item(for: target) != nil else { return }
                if !Self.isAnythingFocused {
                    focusedCard = target
                    return
                }
            }
        }
    }

    /// Whether anything in the app has focus.
    private static var isAnythingFocused: Bool {
        UIApplication.shared.connectedScenes.contains { scene in
            (scene as? UIWindowScene)?.focusSystem?.focusedItem != nil
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
    /// or to the next row when that row went too, instead of falling back to the sidebar. That
    /// includes the card tvOS is about to focus again after Back, when the refresh lands first,
    /// and the card whose long-press menu took it out of its row.
    private func keepFocus(from old: HomeContent, to new: HomeContent) {
        let remembered = lastFocusedByRow.filter { new.item(for: $0.value) != nil }
        lastFocusedByRow = remembered
        guard let card = focusedCard ?? returningCard ?? cardLeft, new.item(for: card) == nil,
              let row = new.nearestRow(to: card.rowID, in: old)
        else { return }
        let target = remembered[row.id] ?? row.firstCard
        scrollTarget = target
        if focusedCard == nil, returningCard == nil {
            // Focus is outside the rows, most likely in the card's own menu, so it isn't taken
            // from there now.
            orphanedFocus = target
            return
        }
        if focusedCard == nil {
            // Back is still under way, and tvOS may focus a card of its own choosing when it ends.
            returningCard = target
        }
        focusedCard = target
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

/// A row's title over its cards. VoiceOver hears the row as a group named by its title, and the
/// title as a heading.
private struct HomeRowView: View {
    let row: HomeRow
    let focusedCard: FocusState<CardID?>.Binding
    let scrollTarget: CardID?

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(row.title)
                .font(.headline)
                .foregroundStyle(theme.onBackground)
                // The row's label reads the title as focus moves in, so it's said once.
                .accessibilityHidden(true)
            ScrollViewReader { scroller in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: CGFloat(row.config.viewOptions.spacing) * HomeCardStyle.spacingPointsPerDp) {
                        ForEach(row.cards) { card in
                            link(to: card) {
                                HomeCardView(card: card, options: row.config.viewOptions, hasMenu: !isLiveTV)
                            }
                            .buttonStyle(.borderless)
                            // The long-press menu, for cards that show an item; genres, studios,
                            // channels and programmes have none.
                            .cardMenu()
                            .focused(focusedCard, equals: CardID(rowID: row.id, itemID: card.id))
                            .accessibilityIdentifier("card.\(row.id).\(card.id)")
                        }
                    }
                    .padding(.vertical, HomeLayout.focusPadding)
                }
                .scrollClipDisabled()
                .onChange(of: scrollTarget) { _, card in
                    // Cards far back along the row may not exist yet, and focus can't move to them
                    // until they do.
                    guard let card, card.rowID == row.id else { return }
                    scroller.scrollTo(card.itemID)
                }
            }
        }
        .focusSection()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: row.title))
        .accessibilityIdentifier("home.row.\(row.id)")
        // Lets the menus of Continue Watching and Next Up cards take them out of their row.
        .environment(\.cardMenuSource, row.config.kind.menuSource)
    }

    /// Channels and programmes open Live TV's own sheet and player, not an item page.
    private var isLiveTV: Bool {
        row.config.kind == .tvChannels || row.config.kind == .tvPrograms
    }

    @ViewBuilder
    private func link(to card: HomeCard, @ViewBuilder label: () -> some View) -> some View {
        switch card.destination {
        case .item where isLiveTV:
            LiveTVHomeCard(item: card.item, isChannel: row.config.kind == .tvChannels, label: label)
        case .item:
            NavigationLink(value: card.item, label: label)
        case let .items(link):
            NavigationLink(value: link, label: label)
        }
    }
}

private extension HomeRowConfig.Kind {
    /// Which watching row this is, for the card menu's Remove from Continue Watching and Remove
    /// from Next Up, as Wholphin's home page passes them.
    var menuSource: ItemMenuSource {
        switch self {
        case .continueWatching: .continueWatching
        case .nextUp: .nextUp
        case .continueWatchingCombined: .continueWatchingAndNextUp
        default: .other
        }
    }
}

enum HomeLayout {
    static let headerHeight: CGFloat = 340
    static let headerSpacing: CGFloat = 24
    static let horizontalInset: CGFloat = 80
    static let rowSpacing: CGFloat = 16
    /// Room above and below each row so the focus lift isn't clipped.
    static let focusPadding: CGFloat = 30
    /// Backdrops are faded and dimmed, so 1080p is plenty even on a 4K screen.
    static let backdropPixelWidth: CGFloat = 1920
}
