import AnemoneCore
import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// The Search tab, with its own navigation.
struct SearchTab: View {
    @State private var stack = PageStack()
    @State private var preferences: SearchPreferences

    init(server: SavedServer, user: SavedUser) {
        _preferences = State(initialValue: SearchPreferences(serverID: server.id, userID: user.id))
    }

    var body: some View {
        NavigationStack(path: $stack.path) {
            SearchPage(preferences: preferences)
                // The search page is the stack's root, which `itemPages(in:)` doesn't reach.
                .environment(\.pageStack, stack)
                .itemPages(in: stack)
        }
    }
}

/// Wholphin's search page (`SearchPage`): results appear as the user types, in a row for each
/// kind of item, or all together in one grid. The system search keyboard does the typing; its
/// dictation stands in for Wholphin's voice search button. Before anything is typed, the page
/// offers recent searches.
///
/// The query and results live here, so they're still showing after Back from a result.
struct SearchPage: View {
    let preferences: SearchPreferences

    @Environment(BrowseModel.self) private var browse
    @Environment(\.pageStack) private var stack
    @AppStorage(Preferences.combinedSearchResults) private var isCombined: Bool
    @State private var query = ""
    @State private var results = SearchResults()
    /// A term to search for at once, without waiting for typing to pause: one picked from recent
    /// searches.
    @State private var immediateTerm: String?
    /// Set when a search is picked or submitted, so focus moves to its results, as in Wholphin.
    @State private var focusesResults = false
    @State private var showsOptions = false
    @FocusState private var focus: ItemFocus?

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: ItemLayout.sectionSpacing) {
                header
                if request.term.isEmpty {
                    RecentSearchesSection(terms: preferences.recent.terms, pick: pick) {
                        preferences.updateRecent { $0.clear() }
                    }
                } else if isCombined {
                    CombinedResults(results: results, focus: $focus)
                } else {
                    SearchRows(results: results, kinds: request.kinds, focus: $focus)
                }
            }
            .padding(.horizontal, ItemLayout.horizontalInset)
            .padding(.bottom, ItemLayout.focusPadding)
        }
        .scrollClipDisabled()
        .searchable(text: $query, prompt: "Movies, shows, people and more")
        .onSubmit(of: .search) {
            focusesResults = true
            remember(request.term)
            moveFocusToResults()
        }
        .task(id: request) {
            await search(request)
        }
        .onChange(of: focus) { _, focus in
            results.memory.note(focus)
        }
        .onChange(of: stack?.path.isEmpty ?? true) { _, isEmpty in
            // Opening a result is what makes a search worth keeping.
            if !isEmpty {
                remember(results.term)
            }
        }
        .sheet(isPresented: $showsOptions) {
            SearchOptionsSheet(
                isCombined: $isCombined,
                kinds: SearchKind.searchable(in: browse.libraries),
                preferences: preferences,
            )
        }
    }

    private var header: some View {
        HStack {
            Spacer()
            Button("View Options", systemImage: "slider.horizontal.3") {
                showsOptions = true
            }
            .accessibilityIdentifier("search.options")
        }
        .font(.callout)
        .focusSection()
    }

    /// What to search for now. Changing any part of it searches again.
    private var request: SearchRequest {
        SearchRequest(
            term: query.trimmingCharacters(in: .whitespacesAndNewlines),
            kinds: SearchKind.searchable(in: browse.libraries, excluding: preferences.excludedKinds),
            isCombined: isCombined,
        )
    }

    private func pick(_ term: String) {
        immediateTerm = term
        focusesResults = true
        query = term
    }

    private func remember(_ term: String) {
        guard !term.isEmpty else { return }
        preferences.updateRecent { $0.add(term) }
    }

    /// Runs the request once typing pauses for 750 ms, as Wholphin does. When only the kinds or
    /// the layout changed, it runs at once, and asks only for what isn't showing yet: a kind
    /// switched back on gets its row, and one switched off just hides its row, as in Wholphin.
    private func search(_ request: SearchRequest) async {
        let term = request.term
        guard !term.isEmpty else {
            results = SearchResults()
            return
        }
        if immediateTerm == term {
            immediateTerm = nil
        } else if results.term != term {
            try? await Task.sleep(for: .milliseconds(750))
            guard !Task.isCancelled else { return }
        }
        if results.term != term {
            results = SearchResults(term: term)
        }
        if request.isCombined {
            await searchCombined(term, kinds: request.kinds)
        } else {
            // A row still searching belongs to a search that was cut short.
            await searchRows(
                term,
                kinds: request.kinds.filter { results.rows[$0] == nil || results.rows[$0] == .searching },
            )
        }
    }

    private func searchRows(_ term: String, kinds: [SearchKind]) async {
        guard !kinds.isEmpty else { return }
        let session = browse.session
        for kind in kinds {
            results.rows[kind] = .searching
        }
        // Each row shows as soon as its own search ends.
        await withTaskGroup(of: (SearchKind, Result<[ItemDetails], any Error>).self) { group in
            for kind in kinds {
                group.addTask { await (kind, attempt { try await session.search(term, for: kind) }) }
            }
            for await (kind, result) in group {
                if let state = state(for: result) {
                    results.rows[kind] = state
                    moveFocusToResults()
                }
            }
        }
        if Task.isCancelled {
            // Rows aren't left saying they're searching while the page is away.
            results.rows = results.rows.filter { $0.value != .searching }
        }
    }

    private func searchCombined(_ term: String, kinds: [SearchKind]) async {
        // A grid still searching belongs to a search that was cut short.
        guard results.combined?.kinds != kinds || results.combined?.state == .searching else { return }
        let session = browse.session
        results.combined = CombinedSearch(kinds: kinds, state: .searching)
        let result = await attempt { try await session.search(term, forAll: kinds) }
        results.combined = state(for: result).map { CombinedSearch(kinds: kinds, state: $0) }
        moveFocusToResults()
    }

    /// `nil` when the search was cut short, by more typing or by leaving the page.
    private func state(for result: Result<[ItemDetails], any Error>) -> SearchResults.State? {
        guard !Task.isCancelled else { return nil }
        switch result {
        case let .success(items):
            return .found(items)
        case let .failure(error as SessionError) where error == .signedOut:
            browse.noteSignedOut()
            return .failed("\(browse.server.name) signed you out. Go to Home to sign in again.")
        case .failure:
            return .failed("Couldn't search \(browse.server.name). Check that it's running, then try again.")
        }
    }

    /// After an immediate search, focus moves to the first row with results once every row
    /// above it has finished, like Wholphin's, so it doesn't jump when a row above fills in.
    private func moveFocusToResults() {
        guard focusesResults else { return }
        if isCombined {
            guard let state = results.combined?.state, state != .searching else { return }
            focusesResults = false
            if case let .found(items) = state, let first = items.first {
                focus = .card(row: SearchKind.combinedRowID, item: first.id)
            }
            return
        }
        for kind in request.kinds {
            switch results.rows[kind] {
            case nil, .searching?:
                return
            case let .found(items)? where !items.isEmpty:
                focusesResults = false
                focus = results.memory.entry(row: kind.rowID, first: items.first?.id)
                return
            default:
                continue
            }
        }
        // Nothing was found.
        focusesResults = false
    }
}

/// What a search asks for.
struct SearchRequest: Equatable {
    let term: String
    let kinds: [SearchKind]
    let isCombined: Bool
}

/// What a search found so far: a state for each row, or for the combined grid.
struct SearchResults {
    enum State: Equatable {
        case searching
        case found([ItemDetails])
        case failed(String)
    }

    var term = ""
    var rows: [SearchKind: State] = [:]
    var combined: CombinedSearch?
    /// Each row's last-focused card. It's part of the results, so a new search enters its rows
    /// at their first cards, not at cards remembered from an earlier search that it may not have.
    var memory = RowMemory()
}

struct CombinedSearch {
    /// The kinds searched for; the grid is searched again when they change.
    let kinds: [SearchKind]
    let state: SearchResults.State
}
