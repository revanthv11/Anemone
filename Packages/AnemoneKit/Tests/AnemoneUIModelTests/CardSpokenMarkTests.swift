import AnemoneUI
import Foundation
import Testing

/// What VoiceOver reads for the marks over a card: the ones the card draws, in the order it draws
/// them, in words.
struct CardSpokenMarkTests {
    @Test func `a card with no marks reads none`() {
        #expect(CardSpokenMark.marks(for: CardMarks()).isEmpty)
        #expect(CardSpokenMark.marks(for: CardMarks(progress: 0)).isEmpty)
    }

    @Test func `marks read in the order the card draws them`() {
        let marks = CardMarks(badges: CardBadges(isFavorite: true, isPlayed: true, unplayedCount: 3))
        #expect(CardSpokenMark.marks(for: marks) == [.favorite, .watched, .unwatched(count: 3)])
    }

    @Test func `a partly watched item reads its progress, not watched`() {
        // The card draws the bar instead of the check, as Wholphin does.
        let marks = CardMarks(badges: CardBadges(isFavorite: true, isPlayed: true), progress: 0.45)
        #expect(CardSpokenMark.marks(for: marks) == [.favorite, .progress(percent: 45)])
    }

    @Test func `no unwatched count is read when every episode is watched`() {
        let marks = CardMarks(badges: CardBadges(isPlayed: true, unplayedCount: 0))
        #expect(CardSpokenMark.marks(for: marks) == [.watched])
    }

    @Test(arguments: [
        (0.001, 1),
        (0.004, 1),
        (0.126, 13),
        (0.5, 50),
        (0.996, 100),
        (1.4, 100),
    ])
    func `progress reads as a whole percentage, a sliver as 1 and past the end as 100`(
        progress: Double,
        percent: Int,
    ) {
        #expect(CardSpokenMark.marks(for: CardMarks(progress: progress)) == [.progress(percent: percent)])
    }

    @Test func `negative progress reads as none`() {
        #expect(CardSpokenMark.marks(for: CardMarks(progress: -0.2)).isEmpty)
    }

    @Test(arguments: [
        (CardSpokenMark.favorite, "Favorite"),
        (.watched, "Watched"),
        (.unwatched(count: 1), "1 unwatched"),
        (.unwatched(count: 12), "12 unwatched"),
        (.progress(percent: 45), "45% watched"),
        (.progress(percent: 100), "100% watched"),
    ])
    func `each mark has its words`(mark: CardSpokenMark, words: String) {
        var spoken = mark.spoken
        spoken.locale = Locale(identifier: "en_US")
        #expect(String(localized: spoken) == words)
    }
}
