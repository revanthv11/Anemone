@testable import AnemoneUI
import Testing

/// Focus going back to the card whose menu opened the player, once the player closes.
@MainActor
struct CardFocusReturnTests {
    @Test func `focus goes back to the card whose menu was open`() throws {
        let focus = CardFocusReturn()
        let first = CardFocusToken()
        let second = CardFocusToken()
        focus.noteFocused(first)
        focus.noteFocused(second)

        let opener = try #require(focus.menuCard)
        focus.returnFocus(to: opener)

        #expect(opener == second)
        #expect(focus.requested == second)
        focus.noteReturned(second)
        #expect(focus.requested == nil)
    }

    @Test func `a card that isn't there any more stops being asked for once another takes focus`() {
        let focus = CardFocusReturn()
        let gone = CardFocusToken()
        let other = CardFocusToken()

        focus.returnFocus(to: gone)
        // Another card's return doesn't answer the request.
        focus.noteReturned(other)
        #expect(focus.requested == gone)
        focus.noteFocused(other)

        #expect(focus.requested == nil)
        #expect(focus.menuCard == other)
    }
}
