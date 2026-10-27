import AnemoneUI
import Testing

/// Changes from card menus showing on every card of their item, until a card's page catches up.
@MainActor
struct CardMarksStoreTests {
    /// An item page's card for a movie in progress.
    private let pageCard = CardMarks(badges: CardBadges(isFavorite: true), progress: 0.3)
    /// A home row's card for the same movie: it knows the progress only.
    private let homeCard = CardMarks(progress: 0.3)
    /// The server's answer to marking the movie watched.
    private let watched = CardMarks(badges: CardBadges(isFavorite: true, isPlayed: true))

    @Test func `a change shows on every card of the item, whatever it was given`() {
        let store = CardMarksStore()

        store.record(watched, for: "m1", replacing: pageCard)

        #expect(store.marks(for: "m1", given: pageCard) == watched)
        // The home card gains the check and loses the progress bar, but not the heart: it never
        // shows one, and the change didn't touch it.
        #expect(store.marks(for: "m1", given: homeCard) == CardMarks(badges: CardBadges(isPlayed: true)))
        #expect(store.marks(for: "m2", given: homeCard) == homeCard)
    }

    @Test func `the menu of any out-of-date card knows what the server said`() {
        let store = CardMarksStore()

        store.record(watched, for: "m1", replacing: homeCard)

        #expect(store.savedMarks(for: "m1", given: pageCard) == watched)
        #expect(store.savedMarks(for: "m1", given: homeCard) == watched)
        // Caught up: its page reloaded after the change.
        #expect(store.savedMarks(for: "m1", given: watched) == nil)
        #expect(store.savedMarks(for: "m2", given: homeCard) == nil)
    }

    @Test func `a card whose page has something newer keeps its own marks`() {
        let store = CardMarksStore()
        store.record(watched, for: "m1", replacing: pageCard)

        // Played again elsewhere since, and its page reloaded: no change has seen this progress.
        let playedSince = CardMarks(badges: CardBadges(isFavorite: true), progress: 0.6)

        #expect(store.marks(for: "m1", given: playedSince) == playedSince)
        #expect(store.savedMarks(for: "m1", given: playedSince) == nil)
    }

    @Test func `a later change shows on cards that had caught up with an earlier one`() {
        let store = CardMarksStore()
        let unwatched = CardMarks(badges: CardBadges(isFavorite: true))
        store.record(watched, for: "m1", replacing: pageCard)

        // Marked unwatched again from a card that never reloaded.
        store.record(unwatched, for: "m1", replacing: pageCard)

        #expect(store.marks(for: "m1", given: pageCard) == unwatched)
        // A card whose page reloaded between the two changes.
        #expect(store.marks(for: "m1", given: watched) == unwatched)
        #expect(store.marks(for: "m1", given: homeCard) == CardMarks())
    }

    @Test func `an item changed back by its page's own button shows changed back on every card`() {
        let store = CardMarksStore()
        let unwatched = CardMarks(badges: CardBadges(isFavorite: true))
        store.record(watched, for: "m1", replacing: homeCard)

        // The item page, opened after the menu's change, marks it unwatched again with its own
        // button, which records the change as menus do.
        store.record(unwatched, for: "m1", replacing: watched)

        // Its page, loaded again, and the home card, which can't tell, both lose the check.
        #expect(store.marks(for: "m1", given: unwatched) == unwatched)
        #expect(store.savedMarks(for: "m1", given: unwatched) == nil)
        #expect(store.marks(for: "m1", given: homeCard) == CardMarks(badges: CardBadges(isFavorite: true)))
        // A card still showing the menu's change catches up too.
        #expect(store.marks(for: "m1", given: watched) == unwatched)
    }

    @Test func `a favourite changed on a home card shows on the item page's card`() {
        let store = CardMarksStore()
        let pageCard = CardMarks(badges: CardBadges(isPlayed: true))
        let homeCard = CardMarks()

        store.record(CardMarks(badges: CardBadges(isFavorite: true, isPlayed: true)), for: "m1", replacing: homeCard)

        #expect(store.marks(for: "m1", given: pageCard) == CardMarks(badges: CardBadges(
            isFavorite: true,
            isPlayed: true,
        )))
        #expect(store.marks(for: "m1", given: homeCard).badges.isFavorite)
    }

    @Test func `an unplayed count changes only on cards that show one`() {
        let store = CardMarksStore()
        let seriesCard = CardMarks(badges: CardBadges(unplayedCount: 4))
        let homeCard = CardMarks()

        store.record(CardMarks(badges: CardBadges(isPlayed: true, unplayedCount: 0)), for: "s1", replacing: seriesCard)

        #expect(store.marks(for: "s1", given: seriesCard) == CardMarks(badges: CardBadges(
            isPlayed: true,
            unplayedCount: 0,
        )))
        #expect(store.marks(for: "s1", given: homeCard) == CardMarks(badges: CardBadges(isPlayed: true)))
        // Another page of the series that already shows the count left after the change.
        let caughtUp = CardMarks(badges: CardBadges(isPlayed: true, unplayedCount: 0))
        #expect(store.savedMarks(for: "s1", given: caughtUp) == nil)
    }

    @Test func `a page catching up hears only of the deletions since it last heard`() {
        let store = CardMarksStore()
        #expect(store.deletions(since: 0).isEmpty)

        store.recordDeletion(of: "m1")
        store.recordDeletion(of: "m2")

        #expect(store.deletedIDs == ["m1", "m2"])
        // A page covered by both deletions hears of both at once when it next updates.
        #expect(store.deletions(since: 0) == ["m1", "m2"])
        #expect(store.deletions(since: 1) == ["m2"])
        #expect(store.deletions(since: 2).isEmpty)
    }
}
