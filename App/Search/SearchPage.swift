import AnemoneCore
import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// The Search tab, with its own navigation.
struct SearchTab: View {
    let server: SavedServer
    let user: SavedUser

    @State private var stack = PageStack()
    /// Read from UserDefaults once, when the tab first shows. `SignedInView` makes this view
    /// again on every update, and State would throw away a copy made in `init` each time.
    @State private var preferences: SearchPreferences?

    var body: some View {
        NavigationStack(path: $stack.path) {
            if let preferences {
                SearchPage(preferences: preferences)
                    // The search page is the stack's root, which `itemPages(in:)` doesn't reach.
                    .environment(\.pageStack, stack)
                    .itemPages(in: stack)
            }
        }
        .onAppear {
            if preferences == nil {
                preferences = SearchPreferences(serverID: server.id, userID: user.id)
            }
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
    /// What's showing, and what each run of the search does next (`SearchState`).
    @State private var search = SearchState()
    @State private var showsOptions = false
    /// The search a link picked, whose results hold on to focus for a moment; see `holdFocus`.
    @State private var linkSubmission: Int?
    /// A link's result that focus moved to, and until when it's moved back there if tvOS takes
    /// focus away: the link has just opened the tab, and tvOS may still be settling focus on the
    /// keyboard.
    @State private var heldFocus: (card: ItemFocus, until: ContinuousClock.Instant)?
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
                    CombinedResults(results: search.results, focus: $focus)
                } else {
                    SearchRows(results: search.results, kinds: request.kinds, focus: $focus)
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
        .deepLinkSearch { term in
            pick(term)
            linkSubmission = search.submissions
        }
        .pageTask(id: run) {
            await perform(run)
        }
        .onChange(of: focus) { old, new in
            holdFocus(from: old, to: new)
            // Noted as focus leaves a row rather than on every move along it, which would redraw
            // every row and card. Entering a row again is when the memory is read.
            if case let .card(row, item) = old, row != new?.cardRow {
                search.results.noteFocus(leaving: SearchCard(row: row, item: item))
            }
        }
        .onChange(of: stack?.path.isEmpty ?? true) { _, isEmpty in
            if !isEmpty {
                openedResult()
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
        SearchRun(request: request, submission: search.submissions)
    }

    /// A recent search, or a link's: searched at once, with focus moving to its results.
    private func pick(_ term: String) {
        search.submit()
        query = term
    }

    /// Wholphin's search button (`onSearchClick`): searches the term at once, without waiting
    /// for typing to pause, then moves focus to its results. Rows that failed are tried again.
    private func submit() {
        search.submit()
    }

    /// Opening a result is what makes a search worth keeping. When a newer term was still
    /// waiting for typing to pause, the result's own term goes back in the field, so Back
    /// returns to those results with focus on the result.
    private func openedResult() {
        let opened = search.openResult(typed: request)
        if opened.restoresTerm {
            query = opened.term
        }
        if !opened.term.isEmpty {
            preferences.updateRecent { $0.add(opened.term) }
        }
    }

    /// Runs the request once typing pauses, or at once when it was picked or submitted, when
    /// only the kinds or the layout changed, or when the page shows again; `SearchState` decides
    /// which, and what to ask for. Opening a result or leaving the app cuts a search short.
    private func perform(_ run: SearchRun) async {
        // Replaced before it got going, as when a link picks a search as the page appears.
        guard !Task.isCancelled else { return }
        let start = search.start(run)
        switch start {
        case .nothing:
            return
        case .waitsForTyping:
            try? await Task.sleep(for: SearchState.typingPause)
            guard !Task.isCancelled else { return }
        case .searchesNow:
            break
        }
        switch search.work(for: run) {
        case let .rows(kinds):
            await searchRows(run.request.term, kinds: kinds, run: run)
        case let .combined(kinds):
            await searchCombined(run.request.term, kinds: kinds, run: run)
        case .none:
            break
        }
        // When everything was already showing, as when the term showing is submitted.
        moveFocusToResults(for: run)
    }

    private func searchRows(_ term: String, kinds: [SearchKind], run: SearchRun) async {
        let session = browse.session
        // Each row shows as soon as its own search ends.
        await withTaskGroup(of: (SearchKind, Result<[ItemDetails], any Error>).self) { group in
            for kind in kinds {
                group.addTask { await (kind, attempt { try await session.search(term, for: kind) }) }
            }
            for await (kind, result) in group {
                guard let state = outcome(of: result) else { continue }
                search.results.record(state, for: kind)
                moveFocusToResults(for: run)
            }
        }
    }

    private func searchCombined(_ term: String, kinds: [SearchKind], run: SearchRun) async {
        let session = browse.session
        let result = await attempt { try await session.search(term, forAll: kinds) }
        guard let state = outcome(of: result) else { return }
        search.results.recordCombined(state, kinds: kinds)
        moveFocusToResults(for: run)
    }

    /// `nil` when the search was cut short, by more typing or by leaving the page.
    private func outcome(of result: Result<[ItemDetails], any Error>) -> SearchResults.State? {
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

    /// After a picked or submitted search, moves focus to its results once they're ready
    /// (`SearchState.focusMove(for:)`), never once it's cut short, as when a result covers the
    /// page.
    private func moveFocusToResults(for run: SearchRun) {
        guard !Task.isCancelled, let card = search.focusMove(for: run) else { return }
        focus = .card(row: card.row, item: card.item)
        if run.submission == linkSubmission {
            linkSubmission = nil
            heldFocus = (.card(row: card.row, item: card.item), .now + .seconds(2))
        }
    }

    /// Moves focus back to a link's result if tvOS takes it to the keyboard just after it got
    /// there, once.
    private func holdFocus(from old: ItemFocus?, to new: ItemFocus?) {
        guard let held = heldFocus, old == held.card else { return }
        heldFocus = nil
        if new == nil, ContinuousClock.now < held.until {
            focus = held.card
        }
    }
}

extension SearchResults {
    /// Each row's last-focused card, for its `CardRow`.
    var memory: RowMemory {
        lastFocused.reduce(into: RowMemory()) { memory, entry in
            memory.note(.card(row: entry.key, item: entry.value))
        }
    }
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
