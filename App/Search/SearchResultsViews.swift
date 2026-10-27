import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// Wholphin's search rows (`SearchRowResult`): a row for each kind, in order, showing
/// "Searching…" until its search ends. Kinds with nothing found are left out.
struct SearchRows: View {
    let results: SearchResults
    let kinds: [SearchKind]
    let focus: FocusState<ItemFocus?>.Binding

    var body: some View {
        ForEach(kinds, id: \.self) { kind in
            switch results.rows[kind] {
            case .searching?:
                SearchPlaceholder(title: kind.title, message: "Searching…")
            case let .failed(message)?:
                SearchPlaceholder(title: kind.title, message: message)
            case let .found(items)? where !items.isEmpty:
                SearchResultsRow(kind: kind, items: items, focus: focus, memory: results.memory)
            case .found?, nil:
                EmptyView()
            }
        }
        if isEmpty {
            SearchPlaceholder(title: "No results", message: "Nothing matches “\(results.term)”.")
                .accessibilityIdentifier("search.noResults")
        }
    }

    /// Whether every row has finished and found nothing.
    private var isEmpty: Bool {
        !kinds.isEmpty && kinds.allSatisfy { results.rows[$0] == .found([]) }
    }
}

/// One kind's results, with Wholphin's card for that kind (`SearchPageCard`).
private struct SearchResultsRow: View {
    let kind: SearchKind
    let items: [ItemDetails]
    let focus: FocusState<ItemFocus?>.Binding
    let memory: RowMemory

    @Environment(BrowseModel.self) private var browse
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        CardRow(id: kind.rowID, title: kind.title, elements: items, focus: focus, memory: memory) { details in
            if kind == .person {
                NavigationLink(value: details.item) {
                    PersonCard(
                        name: details.item.name,
                        role: nil,
                        imageURL: browse.imageURL(
                            details.ownPrimaryImage,
                            width: ItemLayout.personWidth * displayScale,
                        ),
                        width: ItemLayout.personWidth,
                    )
                }
                .buttonStyle(.personCard)
            } else {
                NavigationLink(value: details.item) {
                    ItemCard(details: details, shape: kind.cardShape)
                }
                .buttonStyle(.borderless)
            }
        }
        .accessibilityIdentifier("search.row.\(kind.rowID)")
    }
}

/// Wholphin's combined results (`SearchCombinedResults`): everything found, best match first, in
/// one grid of posters.
struct CombinedResults: View {
    let results: SearchResults
    let focus: FocusState<ItemFocus?>.Binding

    var body: some View {
        switch results.combined?.state {
        case .searching?:
            SearchPlaceholder(title: "Results", message: "Searching…")
        case let .failed(message)?:
            SearchPlaceholder(title: "Results", message: message)
        case let .found(items)? where items.isEmpty:
            SearchPlaceholder(title: "Results", message: "Nothing matches “\(results.term)”.")
                .accessibilityIdentifier("search.noResults")
        case let .found(items)?:
            VStack(alignment: .leading, spacing: 8) {
                Text("Results")
                    .font(.headline)
                LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 40) {
                    ForEach(items) { details in
                        NavigationLink(value: details.item) {
                            ItemCard(details: details, shape: .poster)
                        }
                        .buttonStyle(.borderless)
                        .cardMenu()
                        .focused(focus, equals: .card(row: SearchKind.combinedRowID, item: details.id))
                        .accessibilityIdentifier("card.\(SearchKind.combinedRowID).\(details.id)")
                    }
                }
                .padding(.vertical, ItemLayout.focusPadding)
            }
            .focusSection()
        case nil:
            EmptyView()
        }
    }

    private static let columns = Array(
        repeating: GridItem(.fixed(CardShape.poster.cardWidth), spacing: ItemLayout.cardSpacing, alignment: .top),
        count: 7,
    )
}

/// Before anything is typed: recent searches to pick from again, newest first.
struct RecentSearchesSection: View {
    let terms: [String]
    let pick: (String) -> Void
    let clear: () -> Void

    var body: some View {
        if terms.isEmpty {
            Text("Search your libraries for movies, shows, episodes, people and more.")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("search.hint")
        } else {
            // A list down the page, so focus coming from above lands on the newest search, and
            // clearing is last, out of the way.
            VStack(alignment: .leading, spacing: 16) {
                Text("Recent Searches")
                    .font(.headline)
                ForEach(Array(terms.enumerated()), id: \.element) { index, term in
                    Button(term, systemImage: "clock.arrow.circlepath") {
                        pick(term)
                    }
                    .accessibilityIdentifier("search.recent.\(index)")
                }
                Button("Clear Recent Searches", systemImage: "trash", role: .destructive, action: clear)
                    .accessibilityIdentifier("search.recent.clear")
                    .padding(.top, 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .focusSection()
        }
    }
}

/// In place of results when View Options leaves out every kind: there's nothing to search, so
/// nothing is asked for.
struct NoSearchKinds: View {
    var body: some View {
        SearchPlaceholder(
            title: "No search types selected",
            message: "Choose the types to include in View Options.",
        )
        .accessibilityIdentifier("search.noKinds")
    }
}

/// Wholphin's `SearchResultPlaceholder`: a row's title over what's happening.
private struct SearchPlaceholder: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 32)
    }
}

extension SearchKind {
    /// The row's name in Wholphin (`formatTypeName`).
    var title: String {
        switch self {
        case .movie: "Movies"
        case .series: "TV Shows"
        case .episode: "Episodes"
        case .collection: "Collections"
        case .person: "People"
        case .musicAlbum: "Albums"
        case .musicArtist: "Artists"
        case .audio: "Songs"
        case .musicVideo: "Music Videos"
        case .playlist: "Playlists"
        case .video: "Videos"
        case .photo: "Photos"
        case .photoAlbum: "Photo Albums"
        }
    }

    /// For focus and accessibility identifiers, as in `card.movie.<item>`.
    var rowID: String {
        "\(self)"
    }

    static let combinedRowID = "results"

    /// Wholphin's search cards: 16:9 for episodes, square for music. Videos and photos are 16:9
    /// and playlists square here, as in Anemone's other rows, where Wholphin's search uses 2:3.
    var cardShape: CardShape {
        switch self {
        case .movie, .series, .collection, .person: .poster
        case .episode, .video, .musicVideo, .photo, .photoAlbum: .thumb
        case .musicAlbum, .musicArtist, .audio, .playlist: .square
        }
    }
}
