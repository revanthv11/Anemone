import Foundation

/// What the search page asks for. Changing any part of it searches again.
public struct SearchRequest: Equatable, Sendable {
    public let term: String
    public let kinds: [SearchKind]
    public let isCombined: Bool

    public init(term: String, kinds: [SearchKind], isCombined: Bool) {
        self.term = term
        self.kinds = kinds
        self.isCombined = isCombined
    }

    func with(term: String) -> Self {
        Self(term: term, kinds: kinds, isCombined: isCombined)
    }
}

/// One run of the page's search: the request, and the pick or submission it belongs to, so
/// picking or submitting runs it again even when the request is the same.
public struct SearchRun: Equatable, Sendable {
    public let request: SearchRequest
    public let submission: Int

    public init(request: SearchRequest, submission: Int) {
        self.request = request
        self.submission = submission
    }
}

/// A card on the search page: its row (`SearchKind.rowID`, or the combined grid's) and item.
public struct SearchCard: Hashable, Sendable {
    public let row: String
    public let item: String

    public init(row: String, item: String) {
        self.row = row
        self.item = item
    }
}

/// What a search found so far: a state for each row, or for the combined grid.
public struct SearchResults: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case searching
        case found([ItemDetails])
        case failed(String)

        public var isFound: Bool {
            if case .found = self {
                true
            } else {
                false
            }
        }
    }

    public var term = ""
    public var rows: [SearchKind: State] = [:]
    public var combined: CombinedSearch?
    /// Each row's last-focused card, by row. It's part of the results, so a new search enters its
    /// rows at their first cards, not at cards remembered from an earlier search that it may not
    /// have.
    public private(set) var lastFocused: [String: String] = [:]

    public init(term: String = "") {
        self.term = term
    }

    /// Notes the card focus left its row from, which is where focus enters the row again. A card
    /// these results don't show is ignored: focus leaves a card of the previous term's results
    /// as they're replaced, and the new results don't have it.
    public mutating func noteFocus(leaving card: SearchCard) {
        guard shows(card) else { return }
        lastFocused[card.row] = card.item
    }

    /// Where focus lands on entering a row: its last-focused card, or `first`.
    public func entry(row: String, first: String?) -> String? {
        lastFocused[row] ?? first
    }

    /// Whether these results show `card`.
    public func shows(_ card: SearchCard) -> Bool {
        let state = if card.row == SearchKind.combinedRowID {
            combined?.state
        } else {
            SearchKind.allCases.first { $0.rowID == card.row }.flatMap { rows[$0] }
        }
        guard case let .found(items) = state else { return false }
        return items.contains { $0.id == card.item }
    }

    /// Records what a row's search found. A row that fails to refresh keeps what it found.
    public mutating func record(_ state: State, for kind: SearchKind) {
        if case .failed = state, rows[kind]?.isFound == true {
            return
        }
        rows[kind] = state
    }

    /// Records what the combined grid's search found. A grid that fails to refresh keeps what it
    /// found.
    public mutating func recordCombined(_ state: State, kinds: [SearchKind]) {
        if case .failed = state, combined?.kinds == kinds, combined?.state.isFound == true {
            return
        }
        combined = CombinedSearch(kinds: kinds, state: state)
    }

    /// Rows still searching when more typing cut their search short won't find anything for
    /// this term, so they're hidden rather than saying "Searching…" under it while the next term
    /// waits for typing to pause. Rows that found something keep showing it until then, as in
    /// Wholphin.
    mutating func dropUnfinished() {
        rows = rows.filter { $0.value != .searching }
        if combined?.state == .searching {
            combined = nil
        }
    }
}

public struct CombinedSearch: Equatable, Sendable {
    /// The kinds searched for; the grid is searched again when they change.
    public let kinds: [SearchKind]
    public let state: SearchResults.State

    public init(kinds: [SearchKind], state: SearchResults.State) {
        self.kinds = kinds
        self.state = state
    }
}

/// The search page's state between runs of its search, ported from what Wholphin's
/// `SearchPage` and `SearchViewModel` keep: what's showing, the run started last, and the
/// picked or submitted search that moves focus to its results. The page runs each search
/// (`SearchRun`) as a task and asks this what to do as it starts, as results arrive and as it
/// ends, so those decisions can be tested apart from SwiftUI.
public struct SearchState: Sendable {
    /// How a run goes on once it has started.
    public enum Start: Equatable, Sendable {
        /// Nothing to search: no term, or every kind left out (`/Items` without types would
        /// return every type). The results are cleared.
        case nothing
        /// Waits for typing to pause, as Wholphin does, then searches.
        case waitsForTyping
        case searchesNow
    }

    /// What a run searches once any wait is over.
    public enum Work: Equatable, Sendable {
        case rows([SearchKind])
        case combined([SearchKind])
        case none
    }

    /// How long typing has to pause before a typed search runs, as in Wholphin.
    public static let typingPause = Duration.milliseconds(750)

    public var results = SearchResults()
    /// Counts the searches picked (from recent searches or a link) or submitted, each of which
    /// runs at once, like Wholphin's `triggerImmediateSearch`, even when the query didn't change.
    public private(set) var submissions = 0
    /// The run started last, which tells the page showing again from a new search.
    public private(set) var lastRun: SearchRun?
    /// The picked or submitted search that moves focus to its results once they show, and the
    /// term it was for once its first run started. Like Wholphin's `searchClicked`, it holds
    /// until focus moves, the term changes or a result is opened, so results that come later,
    /// as when the libraries load and add kinds to search, still take focus.
    private var focusing: (submission: Int, term: String?)?
    /// Whether the run started last is the page showing again rather than a new search.
    private var isShowingAgain = false

    public init() {}

    /// A search picked from recent searches or a link, or submitted from the keyboard: it runs
    /// at once, and moves focus to its results.
    public mutating func submit() {
        submissions += 1
        focusing = (submissions, nil)
    }

    /// Starts a run. When the page shows again (after Back from a result, or back in the
    /// foreground), everything is searched again, so cards show their new watched, favourite and
    /// progress state, like Home's and item pages' refresh.
    public mutating func start(_ run: SearchRun) -> Start {
        let request = run.request
        isShowingAgain = run == lastRun
        let isSubmitted = run.submission != lastRun?.submission ?? 0
        lastRun = run
        keepFocusMove(for: run)
        guard !request.term.isEmpty, !request.kinds.isEmpty else {
            results = SearchResults(term: request.term)
            if focusing?.submission == run.submission {
                focusing = nil
            }
            return .nothing
        }
        guard results.term != request.term else { return .searchesNow }
        // More typing cut short what the last term was still searching.
        results.dropUnfinished()
        return isSubmitted || isShowingAgain ? .searchesNow : .waitsForTyping
    }

    /// What to search once any wait is over, with the rows it searches marked as searching.
    /// A new term starts from empty results. When only the kinds or the layout changed, it asks
    /// only for what isn't showing yet: a kind switched back on gets its row, and one switched
    /// off just hides its row, as in Wholphin. Rows already showing results keep them until their
    /// new ones arrive.
    public mutating func work(for run: SearchRun) -> Work {
        let request = run.request
        let refreshes = isShowingAgain && results.term == request.term
        if results.term != request.term {
            results = SearchResults(term: request.term)
        }
        if request.isCombined {
            // Searched again when its kinds change, and when it hasn't found anything yet: never
            // searched, cut short, or failed.
            let isShowing = results.combined?.kinds == request.kinds && results.combined?.state.isFound == true
            guard refreshes || !isShowing else { return .none }
            if !isShowing {
                results.combined = CombinedSearch(kinds: request.kinds, state: .searching)
            }
            return .combined(request.kinds)
        }
        // Rows that haven't found anything yet: never searched, cut short, or failed.
        let kinds = refreshes ? request.kinds : request.kinds.filter { results.rows[$0]?.isFound != true }
        for kind in kinds where results.rows[kind]?.isFound != true {
            results.rows[kind] = .searching
        }
        return kinds.isEmpty ? .none : .rows(kinds)
    }

    /// After a picked or submitted search, the card focus moves to: the first row with results,
    /// once every row above it has finished, like Wholphin's, so it doesn't jump when a row above
    /// fills in. Only that search's own results take it, never rows left from an earlier term.
    /// `nil` while rows above are still searching, when nothing was found, and once focus has
    /// moved.
    public mutating func focusMove(for run: SearchRun) -> SearchCard? {
        guard let focusing, focusing.submission == run.submission, focusing.term == run.request.term,
              results.term == run.request.term
        else { return nil }
        if run.request.isCombined {
            guard case let .found(items)? = results.combined?.state, let first = items.first else { return nil }
            self.focusing = nil
            return SearchCard(row: SearchKind.combinedRowID, item: first.id)
        }
        for kind in run.request.kinds {
            switch results.rows[kind] {
            case nil, .searching?:
                return nil
            case let .found(items)? where !items.isEmpty:
                self.focusing = nil
                let item = results.entry(row: kind.rowID, first: items.first?.id)
                return item.map { SearchCard(row: kind.rowID, item: $0) }
            default:
                continue
            }
        }
        return nil
    }

    /// A result was opened, which makes its search worth keeping: returns that term. Back returns
    /// focus to the result, so a picked search that hadn't moved focus yet doesn't any more. When
    /// a newer term was still waiting for typing to pause, the result belongs to the term showing,
    /// so that term goes back in the field (`restoresTerm`) and Back returns to its results with
    /// focus on the card, rather than replacing them with the newer term's.
    public mutating func openResult(typed request: SearchRequest) -> (term: String, restoresTerm: Bool) {
        focusing = nil
        let term = results.term
        guard !term.isEmpty, term != request.term else { return (term, false) }
        lastRun = SearchRun(request: request.with(term: term), submission: submissions)
        return (term, true)
    }

    /// Whether a picked or submitted search still moves focus once this run starts. A change of
    /// kinds or layout restarts the run and keeps it, and so does the app coming back to the
    /// foreground; more typing (a new term) ends it.
    private mutating func keepFocusMove(for run: SearchRun) {
        // A run from before the pick that only starts now, as when a link picks a search while
        // the page appears, leaves it to the pick's own run.
        guard let focusing, focusing.submission == run.submission else { return }
        if let term = focusing.term {
            if term != run.request.term {
                self.focusing = nil
            }
        } else {
            self.focusing = (focusing.submission, run.request.term)
        }
    }
}

public extension SearchKind {
    /// For focus and accessibility identifiers, as in `card.movie.<item>`.
    var rowID: String {
        "\(self)"
    }

    /// The combined grid's row, for focus and accessibility identifiers.
    static let combinedRowID = "results"
}
