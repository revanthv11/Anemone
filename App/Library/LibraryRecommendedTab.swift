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
    @State private var content = Content.loading
    @State private var focus = FocusedTitle()
    @FocusState private var focusedCard: CardID?
    @State private var lastFocusedByRow: [RecommendedRow.Kind: CardID] = [:]

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
                message("Nothing to recommend in \(library.name) yet.") {}
            case .loaded, .failed:
                message("Couldn't load recommendations for \(library.name) from \(browse.server.name).") {
                    Button("Try again") {
                        Task { await load() }
                    }
                }
            case .signedOut:
                message("\(browse.server.name) signed you out. Go to Home to sign in again.") {}
            }
        }
        .task {
            await load()
        }
    }

    private func rows(_ recommended: RecommendedContent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            LibraryDetailsHeader(focus: focus)
                .padding(.horizontal, GridLayout.horizontalInset)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: RecommendedLayout.rowSpacing) {
                    ForEach(recommended.rows) { row in
                        RecommendedRowView(row: row, focusedCard: $focusedCard, onSelect: { path.append($0) })
                            .defaultFocus(
                                $focusedCard,
                                lastFocusedByRow[row.kind] ?? row.firstCard,
                                priority: .userInitiated,
                            )
                    }
                    if !recommended.failedRows.isEmpty {
                        NoticeText("Some rows couldn't be loaded.")
                    }
                }
                .padding(.horizontal, GridLayout.horizontalInset)
                .padding(.bottom, GridLayout.focusPadding)
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
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            actions()
        }
        // Gives focus somewhere to rest, so the tabs and the sidebar stay in reach.
        .focusable()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        case .continueWatching: "Continue Watching"
        case .nextUp: "Next Up"
        case .recentlyReleased: "Recently Released"
        case .recentlyAdded: "Recently Added"
        case .topUnwatched: "Top Unwatched"
        case .suggestions: "Suggestions"
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(row.title)
                .font(.headline)
            ScrollView(.horizontal) {
                LazyHStack(spacing: RecommendedLayout.cardSpacing) {
                    ForEach(row.items) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            MediaCard(
                                title: item.displayTitle,
                                subtitle: item.subtitle ?? item.year.map(String.init),
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
    }
}

private enum RecommendedLayout {
    static let rowSpacing: CGFloat = 16
    static let cardSpacing: CGFloat = 40
    static let cardWidth: CGFloat = 200
}
