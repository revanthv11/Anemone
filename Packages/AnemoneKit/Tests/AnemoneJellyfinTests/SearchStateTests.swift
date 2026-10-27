@testable import AnemoneJellyfin
import Testing

/// The search page's decisions as its runs start, find things and end (`SearchState`).
struct SearchStateTests {
    @Test func `a typed term waits for typing to pause, then searches every row`() {
        var state = SearchState()
        let run = run("th")

        #expect(state.start(run) == .waitsForTyping)
        #expect(state.work(for: run) == .rows([.movie, .series]))
        #expect(state.results.term == "th")
        #expect(state.results.rows == [.movie: .searching, .series: .searching])
        // Typed, so focus stays on the keyboard.
        state.results.record(.found([item("m1")]), for: .movie)
        state.results.record(.found([]), for: .series)
        #expect(state.focusMove(for: run) == nil)
    }

    @Test func `a picked term searches at once and moves focus to the first row with results`() {
        var state = SearchState()
        state.submit()
        let run = run("th", submission: 1)

        #expect(state.start(run) == .searchesNow)
        #expect(state.work(for: run) == .rows([.movie, .series]))
        state.results.record(.found([item("s1")]), for: .series)
        // Movies is still searching, so focus waits for it.
        #expect(state.focusMove(for: run) == nil)
        state.results.record(.found([]), for: .movie)
        #expect(state.focusMove(for: run) == SearchCard(row: "series", item: "s1"))
        // Only once.
        #expect(state.focusMove(for: run) == nil)
    }

    @Test func `a card from the previous term's results isn't remembered for the new ones`() {
        var state = SearchState()
        let first = run("cami")
        _ = state.start(first)
        _ = state.work(for: first)
        state.results.record(.found([item("m1"), item("m2")]), for: .movie)
        state.results.noteFocus(leaving: SearchCard(row: "movie", item: "m2"))
        #expect(state.results.entry(row: "movie", first: "m1") == "m2")

        let second = run("st. louis")
        _ = state.start(second)
        _ = state.work(for: second)
        state.results.record(.found([item("m3"), item("m4")]), for: .movie)
        // Focus leaves the old results' card as they're replaced.
        state.results.noteFocus(leaving: SearchCard(row: "movie", item: "m2"))

        #expect(state.results.entry(row: "movie", first: "m3") == "m3")
        state.results.noteFocus(leaving: SearchCard(row: "movie", item: "m4"))
        #expect(state.results.entry(row: "movie", first: "m3") == "m4")
    }

    @Test func `the combined grid remembers only its own cards`() {
        var state = SearchState()
        let run = run("th", combined: true)
        _ = state.start(run)
        #expect(state.work(for: run) == .combined([.movie, .series]))
        state.results.recordCombined(.found([item("m1")]), kinds: [.movie, .series])

        #expect(state.results.shows(SearchCard(row: SearchKind.combinedRowID, item: "m1")))
        #expect(!state.results.shows(SearchCard(row: SearchKind.combinedRowID, item: "m9")))
        #expect(!state.results.shows(SearchCard(row: "movie", item: "m1")))
    }

    @Test func `opening a result while a new term waits keeps the term showing, and Back refreshes it`() {
        var state = SearchState()
        let showing = run("cami")
        _ = state.start(showing)
        _ = state.work(for: showing)
        state.results.record(.found([item("m1"), item("m2")]), for: .movie)
        state.results.record(.found([]), for: .series)
        // More typing, then a result opened before typing paused for long enough.
        let typed = run("camin")
        #expect(state.start(typed) == .waitsForTyping)

        let opened = state.openResult(typed: typed.request)

        #expect(opened.term == "cami")
        #expect(opened.restoresTerm)
        // Back: the page shows again with the term put back, which refreshes its results in
        // place rather than replacing them, so focus stays on the opened card.
        let back = run("cami")
        #expect(state.start(back) == .searchesNow)
        #expect(state.work(for: back) == .rows([.movie, .series]))
        #expect(state.results.rows[.movie] == .found([item("m1"), item("m2")]))
    }

    @Test func `opening a result of the term searched keeps the field as it is`() {
        var state = SearchState()
        let run = run("cami")
        _ = state.start(run)
        _ = state.work(for: run)

        let opened = state.openResult(typed: run.request)

        #expect(opened.term == "cami")
        #expect(!opened.restoresTerm)
    }

    @Test func `back from a result searches every row again without moving focus`() {
        var state = SearchState()
        state.submit()
        let run = run("th", submission: 1)
        _ = state.start(run)
        _ = state.work(for: run)
        // A result opened before the results came, cutting the run short.
        _ = state.openResult(typed: run.request)

        #expect(state.start(run) == .searchesNow)
        #expect(state.work(for: run) == .rows([.movie, .series]))
        state.results.record(.found([item("m1")]), for: .movie)
        state.results.record(.found([]), for: .series)
        #expect(state.focusMove(for: run) == nil)
    }

    @Test func `a picked search cut short by the app leaving the foreground still moves focus`() {
        var state = SearchState()
        state.submit()
        let run = run("st. louis", submission: 1)
        _ = state.start(run)
        _ = state.work(for: run)
        // Cut short as the app goes inactive, say as a link opens; back in the foreground, the
        // page shows again and the same run starts over.
        #expect(state.start(run) == .searchesNow)
        _ = state.work(for: run)
        state.results.record(.found([item("m1")]), for: .movie)
        state.results.record(.found([]), for: .series)
        #expect(state.focusMove(for: run) == SearchCard(row: "movie", item: "m1"))
    }

    @Test func `a kind or layout change during a picked search keeps its focus move`() {
        var state = SearchState()
        state.submit()
        let picked = run("th", kinds: [.movie], submission: 1)
        _ = state.start(picked)
        _ = state.work(for: picked)
        // The libraries load, say, adding a kind: the run starts again with the same pick,
        // cutting the first one short.
        let restarted = run("th", kinds: [.movie, .series], submission: 1)
        #expect(state.start(restarted) == .searchesNow)

        // Movies was cut short, so it's searched again along with the new kind.
        #expect(state.work(for: restarted) == .rows([.movie, .series]))
        state.results.record(.found([item("m1")]), for: .movie)
        state.results.record(.found([]), for: .series)
        #expect(state.focusMove(for: restarted) == SearchCard(row: "movie", item: "m1"))
    }

    @Test func `a run from before a pick that starts late leaves the pick's focus move alone`() {
        var state = SearchState()
        // A link picks a search as the page appears, before the page's first run, with nothing
        // typed, gets going.
        state.submit()
        let empty = run("", submission: 0)
        #expect(state.start(empty) == .nothing)

        let picked = run("st. louis", submission: 1)
        #expect(state.start(picked) == .searchesNow)
        _ = state.work(for: picked)
        state.results.record(.found([item("m1")]), for: .movie)
        state.results.record(.found([]), for: .series)
        #expect(state.focusMove(for: picked) == SearchCard(row: "movie", item: "m1"))
    }

    @Test func `switching to combined results during a picked search moves focus to the grid`() {
        var state = SearchState()
        state.submit()
        let picked = run("th", submission: 1)
        _ = state.start(picked)
        _ = state.work(for: picked)
        let combined = run("th", submission: 1, combined: true)
        _ = state.start(combined)

        #expect(state.work(for: combined) == .combined([.movie, .series]))
        state.results.recordCombined(.found([item("e1")]), kinds: [.movie, .series])
        #expect(state.focusMove(for: combined) == SearchCard(row: SearchKind.combinedRowID, item: "e1"))
    }

    @Test func `more typing during a picked search ends its focus move`() {
        var state = SearchState()
        state.submit()
        let picked = run("th", submission: 1)
        _ = state.start(picked)
        _ = state.work(for: picked)
        let typed = run("the", submission: 1)
        _ = state.start(typed)

        _ = state.work(for: typed)
        state.results.record(.found([item("m1")]), for: .movie)
        state.results.record(.found([]), for: .series)
        #expect(state.focusMove(for: typed) == nil)
    }

    @Test func `a picked search that found nothing moves focus once a kind added later finds something`() {
        var state = SearchState()
        state.submit()
        // Before the libraries load, only people are searched.
        let picked = run("st. louis", kinds: [.person], submission: 1)
        _ = state.start(picked)
        _ = state.work(for: picked)
        state.results.record(.found([]), for: .person)
        #expect(state.focusMove(for: picked) == nil)

        let loaded = run("st. louis", kinds: [.movie, .person], submission: 1)
        #expect(state.start(loaded) == .searchesNow)
        #expect(state.work(for: loaded) == .rows([.movie]))
        state.results.record(.found([item("m1")]), for: .movie)
        #expect(state.focusMove(for: loaded) == SearchCard(row: "movie", item: "m1"))
    }

    @Test func `rows cut short by more typing stop saying they're searching`() {
        var state = SearchState()
        let first = run("st")
        _ = state.start(first)
        _ = state.work(for: first)
        state.results.record(.found([item("m1")]), for: .movie)
        #expect(state.results.rows[.series] == .searching)

        #expect(state.start(run("st.")) == .waitsForTyping)

        // While the new term waits, the old term's rows that found something stay, and the one
        // cut short is hidden instead of saying "Searching…".
        #expect(state.results.term == "st")
        #expect(state.results.rows == [.movie: .found([item("m1")])])
    }

    @Test func `a combined grid cut short by more typing stops saying it's searching`() {
        var state = SearchState()
        let first = run("st", combined: true)
        _ = state.start(first)
        _ = state.work(for: first)
        #expect(state.results.combined?.state == .searching)

        _ = state.start(run("st.", combined: true))

        #expect(state.results.combined == nil)
    }

    @Test func `a kind switched back on searches only its row`() {
        var state = SearchState()
        let first = run("th", kinds: [.movie])
        _ = state.start(first)
        _ = state.work(for: first)
        state.results.record(.found([item("m1")]), for: .movie)

        let more = run("th", kinds: [.movie, .series])
        #expect(state.start(more) == .searchesNow)
        #expect(state.work(for: more) == .rows([.series]))
        #expect(state.results.rows[.movie] == .found([item("m1")]))
    }

    @Test func `a row that fails to refresh keeps what it found`() {
        var results = SearchResults(term: "th")
        results.record(.found([item("m1")]), for: .movie)
        results.record(.failed("Couldn't search"), for: .movie)
        results.record(.failed("Couldn't search"), for: .series)

        #expect(results.rows[.movie] == .found([item("m1")]))
        #expect(results.rows[.series] == .failed("Couldn't search"))
    }

    @Test func `nothing to search clears the results and any focus move`() {
        var state = SearchState()
        state.submit()
        let none = SearchRun(request: SearchRequest(term: "th", kinds: [], isCombined: false), submission: 1)

        #expect(state.start(none) == .nothing)
        #expect(state.results == SearchResults(term: "th"))
        // Switching the kinds back on brings results, without taking focus.
        let back = run("th", submission: 1)
        _ = state.start(back)
        _ = state.work(for: back)
        state.results.record(.found([item("m1")]), for: .movie)
        state.results.record(.found([]), for: .series)
        #expect(state.focusMove(for: back) == nil)
    }

    private func run(
        _ term: String,
        kinds: [SearchKind] = [.movie, .series],
        submission: Int = 0,
        combined: Bool = false,
    ) -> SearchRun {
        SearchRun(request: SearchRequest(term: term, kinds: kinds, isCombined: combined), submission: submission)
    }

    private func item(_ id: String) -> ItemDetails {
        ItemDetails(item: MediaItem(id: id, name: id, kind: .movie))
    }
}
