import AnemoneCore
import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// A library's Recommended tab, from Wholphin's `RecommendedMovie` and `RecommendedTvShow`: rows
/// of what to watch, under a header for the focused title and over its backdrop, as Wholphin
/// draws them with its home page's rows.
///
/// Rows sit in a plain `VStack`, as on the home page, and each remembers its last-focused card
/// through `defaultFocus`; see docs/spikes/home-focus.md. Like Wholphin's, the rows load once
/// when the tab opens.
struct LibraryRecommendedTab: View {
    let library: Library
    @Binding var path: NavigationPath
    var onPastFirstRow: (Bool) -> Void = { _ in }

    @Environment(BrowseModel.self) private var browse
    @Environment(\.theme) private var theme
    @State private var content = Content.loading
    @State private var focus = FocusedTitle()
    @FocusState private var focusedCard: CardID?
    @State private var lastFocusedByRow: [RecommendedRow.Kind: CardID] = [:]
    /// The rows' scroll view and last row, so the last row can be scrolled to the top too.
    @State private var viewportHeight: CGFloat = 0
    @State private var lastRowHeight: CGFloat = 0

    private enum Content {
        case loading
        case loaded(RecommendedContent)
        case failed
        case signedOut
    }

    var body: some View {
        Group {
            switch content {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .loaded(recommended) where !recommended.rows.isEmpty:
                rows(recommended)
            case let .loaded(recommended) where recommended.failedRows.isEmpty:
                message(String(localized: "Nothing to recommend in \(library.name) yet.")) {}
            case .loaded, .failed:
                message(
                    String(localized: "Couldn't load recommendations for \(library.name) from \(browse.server.name)."),
                ) {
                    Button("Try again") {
                        Task { await load() }
                    }
                }
            case .signedOut:
                message(String(localized: "\(browse.server.name) signed you out. Go to Home to sign in again.")) {}
            }
        }
        .task {
            await load()
        }
        // After Back from a title's page the rows load again, as Wholphin's do, so what was
        // watched or marked there shows; Suggestions stay as they were. A deleted title is
        // dropped at once, below, since the reload can come later.
        .onChange(of: path.count) { old, new in
            if old > 0, new == 0 {
                Task { await refresh() }
            }
        }
        .onItemsDeleted { deleted in
            guard case let .loaded(recommended) = content else { return }
            let remaining = recommended.removing(deleted)
            content = .loaded(remaining)
            // The header goes back to the first title, as when the tab loaded.
            if focus.details?.item.wasDeleted(in: deleted) == true {
                focus.details = remaining.rows.first?.items.first.map { ItemDetails(item: $0) }
            }
        }
    }

    private func rows(_ recommended: RecommendedContent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            LibraryDetailsHeader(focus: focus)
                .padding(.horizontal, GridLayout.horizontalInset)
                .padding(.bottom, LibraryDetailsLayout.spacingBelowHeader)
            ScrollViewReader { scroller in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: RecommendedLayout.rowSpacing) {
                        ForEach(recommended.rows) { row in
                            RecommendedRowView(row: row, focusedCard: $focusedCard, onSelect: { path.append($0) })
                                .defaultFocus(
                                    $focusedCard,
                                    lastFocusedByRow[row.kind] ?? row.firstCard,
                                    priority: .userInitiated,
                                )
                                .id(row.kind)
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                                    if row.kind == recommended.rows.last?.kind {
                                        lastRowHeight = height
                                    }
                                }
                        }
                        if !recommended.failedRows.isEmpty {
                            NoticeText(String(localized: "Some rows couldn't be loaded."))
                        }
                    }
                    .padding(.horizontal, GridLayout.horizontalInset)
                    // Enough below the last row for it to reach the top of the view too.
                    .padding(.bottom, max(GridLayout.focusPadding, viewportHeight - lastRowHeight))
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
                .onChange(of: focusedCard) { _, card in
                    // The focused row's title goes to the top, under the header, as on an item
                    // page. Left to tvOS, the row lands anywhere that shows the card, and the
                    // bottom of the row above it then shows cut off under the header's overview.
                    guard let card else { return }
                    withAnimation { scroller.scrollTo(card.row, anchor: .top) }
                }
            }
        }
        .background {
            LibraryBackdrop(focus: focus)
        }
        .onChange(of: focusedCard) { _, card in
            guard let card, let rowIndex = recommended.rows.firstIndex(where: { $0.kind == card.row }),
                  let item = recommended.rows[rowIndex].items.first(where: { $0.id == card.item })
            else { return }
            lastFocusedByRow[card.row] = card
            focus.details = ItemDetails(item: item)
            // Wholphin shows the tabs while focus is in the first row.
            onPastFirstRow(rowIndex > 0)
        }
    }

    private func message(_ text: String, @ViewBuilder actions: () -> some View) -> some View {
        VStack(spacing: 24) {
            Text(text)
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
            actions()
        }
        // Gives focus somewhere to rest, so the tabs and the sidebar stay in reach.
        .focusable()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Loads every row but Suggestions again and keeps what's showing when that fails.
    private func refresh() async {
        guard case let .loaded(current) = content else { return }
        let kept: Set<RecommendedRow.Kind> = [.suggestions]
        do {
            let fresh = try await browse.session.recommended(
                in: library,
                rows: library.recommendedRows.filter { !kept.contains($0) },
                itemsPerRow: Preferences.maxItemsPerRow.value(),
                enableRewatchingNextUp: Preferences.enableRewatchingNextUp.value(),
            )
            guard !Task.isCancelled, case .loaded = content else { return }
            content = .loaded(current.merging(fresh, keeping: kept, order: library.recommendedRows))
        } catch SessionError.signedOut {
            browse.noteSignedOut()
            content = .signedOut
        } catch {
            // What's showing stays, as a row that fails to load again would only vanish.
        }
    }

    private func load() async {
        do {
            // Settings › Home's row length and Next Up rewatching apply here too, as in Wholphin.
            let recommended = try await browse.session.recommended(
                in: library,
                itemsPerRow: Preferences.maxItemsPerRow.value(),
                enableRewatchingNextUp: Preferences.enableRewatchingNextUp.value(),
            )
            guard !Task.isCancelled else { return }
            if let first = recommended.rows.first?.items.first {
                focus.details = ItemDetails(item: first)
            }
            content = .loaded(recommended)
        } catch SessionError.signedOut {
            browse.noteSignedOut()
            content = .signedOut
        } catch {
            guard !Task.isCancelled else { return }
            content = .failed
        }
    }
}

/// A card's focus identity. The same title can be in more than one row.
private struct CardID: Hashable {
    let row: RecommendedRow.Kind
    let item: MediaItem.ID
}

private extension RecommendedRow {
    var firstCard: CardID? {
        items.first.map { CardID(row: kind, item: $0.id) }
    }

    /// Wholphin's row titles.
    var title: String {
        switch kind {
        case .continueWatching: String(localized: "Continue Watching")
        case .nextUp: String(localized: "Next Up")
        case .recentlyReleased: String(localized: "Recently Released")
        case .recentlyAdded: String(localized: "Recently Added")
        case .topUnwatched: String(localized: "Top Unwatched")
        case .suggestions: String(localized: "Suggestions")
        }
    }
}

/// One row of posters. Wholphin draws these rows with its home page's default style: posters,
/// with episodes showing their series' poster. A long press opens the card menu.
private struct RecommendedRowView: View {
    let row: RecommendedRow
    let focusedCard: FocusState<CardID?>.Binding
    let onSelect: (MediaItem) -> Void

    @Environment(BrowseModel.self) private var browse
    @Environment(\.displayScale) private var displayScale
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(row.title)
                .font(.headline)
                .foregroundStyle(theme.onBackground)
                // The row's label reads the title as focus moves in, so it's said once.
                .accessibilityHidden(true)
            ScrollView(.horizontal) {
                LazyHStack(spacing: RecommendedLayout.cardSpacing) {
                    ForEach(row.items) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            MediaCard(
                                title: item.displayTitle,
                                subtitle: item.subtitle ?? item.year.map(String.init),
                                spokenSubtitle: item.spokenSubtitle,
                                imageURL: browse.imageURL(
                                    item.posterImage,
                                    width: RecommendedLayout.cardWidth * displayScale,
                                ),
                                shape: .poster,
                                width: RecommendedLayout.cardWidth,
                                progress: item.progress,
                                menuItem: CardMenuItem(item),
                            )
                        }
                        .buttonStyle(.borderless)
                        // Wholphin's card menu, without the entries that take a card out of
                        // Continue Watching or Next Up, as its Recommended rows leave them out.
                        .cardMenu()
                        .focused(focusedCard, equals: CardID(row: row.kind, item: item.id))
                        .accessibilityIdentifier("card.recommended.\(row.kind.rawValue).\(item.id)")
                    }
                }
                .padding(.vertical, GridLayout.focusPadding)
            }
            .scrollClipDisabled()
        }
        .focusSection()
        // VoiceOver hears the row as a group named by its title, as on Home.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: row.title))
        .accessibilityIdentifier("library.row.\(row.kind.rawValue)")
    }
}

private enum RecommendedLayout {
    static let rowSpacing: CGFloat = 16
    static let cardSpacing: CGFloat = 40
    static let cardWidth: CGFloat = 200
}
