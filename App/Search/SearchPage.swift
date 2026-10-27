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
    /// Counts the searches picked from recent searches or submitted, each of which runs at once,
    /// like Wholphin's `triggerImmediateSearch`, even when the query didn't change.
    @State private var submissions = 0
    /// Set when a search is picked or submitted, so focus moves to its results, as in Wholphin.
    /// That search clears it when it ends, however it ends, so a later search, typed, doesn't
    /// take focus from the keyboard.
    @State private var focusesResults = false
    /// The run started last, which tells the page showing again from a new search.
    @State private var lastRun: SearchRun?
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
                } else if request.kinds.isEmpty {
                    NoSearchKinds()
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
            submit()
        }
        .pageTask(id: run) {
            await search(run)
        }
        .onChange(of: focus) { old, new in
            // Noted as focus leaves a row rather than on every move along it, which would redraw
            // every row and card. Entering a row again is when the memory is read.
            if let row = old?.cardRow, row != new?.cardRow {
                results.memory.note(old)
            }
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

    private var run: SearchRun {
        SearchRun(request: request, submission: submissions)
    }

    private func pick(_ term: String) {
        submissions += 1
        focusesResults = true
        query = term
    }

    /// Wholphin's search button (`onSearchClick`): searches the term at once, without waiting
    /// for typing to pause, then moves focus to its results. Rows that failed are tried again.
    private func submit() {
        submissions += 1
        focusesResults = true
    }

    private func remember(_ term: String) {
        guard !term.isEmpty else { return }
        preferences.updateRecent { $0.add(term) }
    }

    /// Runs the request once typing pauses for 750 ms, as Wholphin does, or at once when it was
    /// picked or submitted. When only the kinds or the layout changed, it runs at once, and asks
    /// only for what isn't showing yet: a kind switched back on gets its row, and one switched
    /// off just hides its row, as in Wholphin.
    ///
    /// When the page shows again (after Back from a result, or when the app returns to the
    /// foreground), everything is searched again, so cards show their new watched, favourite
    /// and progress state, like Home's and item pages' refresh. Opening a result or leaving the
    /// app cuts a search short.
    private func search(_ run: SearchRun) async {
        let request = run.request
        let term = request.term
        let isShowingAgain = run == lastRun
        let isSubmitted = run.submission != lastRun?.submission
        lastRun = run
        defer {
            // Done with focus, whether it moved there, found nothing or was cut short, unless
            // another pick or submission has taken over.
            if run.submission == submissions {
                focusesResults = false
            }
        }
        // With every kind left out there's nothing to ask for: `/Items` without types would
        // return every type.
        guard !term.isEmpty, !request.kinds.isEmpty else {
            results = SearchResults(term: term)
            return
        }
        if results.term != term {
            if !isSubmitted, !isShowingAgain {
                try? await Task.sleep(for: .milliseconds(750))
                guard !Task.isCancelled else { return }
            }
            results = SearchResults(term: term)
        }
        if request.isCombined {
            await searchCombined(term, kinds: request.kinds, refreshes: isShowingAgain, run: run)
        } else {
            // Rows that haven't found anything yet: never searched, cut short, or failed.
            let kinds = isShowingAgain ? request.kinds : request.kinds.filter { results.rows[$0]?.isFound != true }
            await searchRows(term, kinds: kinds, run: run)
        }
        // When everything was already showing, as when the term showing is submitted.
        moveFocusToResults(for: run)
    }

    private func searchRows(_ term: String, kinds: [SearchKind], run: SearchRun) async {
        guard !kinds.isEmpty else { return }
        let session = browse.session
        // Rows already showing results keep them until their new ones arrive.
        for kind in kinds where results.rows[kind]?.isFound != true {
            results.rows[kind] = .searching
        }
        // Each row shows as soon as its own search ends.
        await withTaskGroup(of: (SearchKind, Result<[ItemDetails], any Error>).self) { group in
            for kind in kinds {
                group.addTask { await (kind, attempt { try await session.search(term, for: kind) }) }
            }
            for await (kind, result) in group {
                guard let state = state(for: result) else { continue }
                // A row that fails to refresh keeps what it found.
                if case .failed = state, results.rows[kind]?.isFound == true {
                    continue
                }
                results.rows[kind] = state
                moveFocusToResults(for: run)
            }
        }
    }

    private func searchCombined(_ term: String, kinds: [SearchKind], refreshes: Bool, run: SearchRun) async {
        // The grid is searched again when its kinds change, and when it hasn't found anything
        // yet: never searched, cut short, or failed.
        let isShowing = results.combined?.kinds == kinds && results.combined?.state.isFound == true
        guard refreshes || !isShowing else { return }
        let session = browse.session
        if !isShowing {
            results.combined = CombinedSearch(kinds: kinds, state: .searching)
        }
        let result = await attempt { try await session.search(term, forAll: kinds) }
        guard let state = state(for: result) else { return }
        // A grid that fails to refresh keeps what it found.
        if case .failed = state, isShowing {
            return
        }
        results.combined = CombinedSearch(kinds: kinds, state: state)
        moveFocusToResults(for: run)
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

    /// After a picked or submitted search, focus moves to the first row with results once every
    /// row above it has finished, like Wholphin's, so it doesn't jump when a row above fills in.
    /// Only that search's own results take it, never rows left from an earlier term, and never
    /// once it's cut short, as when a result covers the page.
    private func moveFocusToResults(for run: SearchRun) {
        guard focusesResults, run.submission == submissions, results.term == run.request.term,
              !Task.isCancelled else { return }
        if run.request.isCombined {
            guard let state = results.combined?.state, state != .searching else { return }
            focusesResults = false
            if case let .found(items) = state, let first = items.first {
                focus = .card(row: SearchKind.combinedRowID, item: first.id)
            }
            return
        }
        for kind in run.request.kinds {
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

/// One run of the page's search: the request, and the pick or submission it belongs to, so
/// picking or submitting runs it again even when the request is the same.
struct SearchRun: Equatable {
    let request: SearchRequest
    let submission: Int
}

/// What a search found so far: a state for each row, or for the combined grid.
struct SearchResults {
    enum State: Equatable {
        case searching
        case found([ItemDetails])
        case failed(String)

        var isFound: Bool {
            if case .found = self {
                true
            } else {
                false
            }
        }
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

private extension ItemFocus {
    /// The row of a focused card.
    var cardRow: String? {
        if case let .card(row, _) = self {
            row
        } else {
            nil
        }
    }
}
