@testable import AnemoneJellyfin
import Testing

/// What waits for a programme's details to close: on Home, the refresh after a recording changed
/// mustn't run while the sheet is up, since it can take the card showing the sheet out of its row.
struct LiveTVSheetFollowUpTests {
    @Test func `a recording changed refreshes once the sheet has closed, and only once`() {
        var followUp = LiveTVSheetFollowUp<String>()

        followUp.recordingChanged()
        let whileOpen = followUp.refreshes
        let closed = followUp.sheetClosed()
        let closedAgain = followUp.sheetClosed()

        // Nothing runs until the sheet says it closed.
        #expect(whileOpen)
        #expect(closed.refreshes)
        #expect(closed.playback == nil)
        #expect(!closedAgain.refreshes)
    }

    @Test func `watch live plays once the sheet has closed`() {
        var followUp = LiveTVSheetFollowUp<String>()

        followUp.play("channel 1")
        let closed = followUp.sheetClosed()
        let closedAgain = followUp.sheetClosed()

        #expect(closed.playback == "channel 1")
        #expect(!closed.refreshes)
        #expect(closedAgain.playback == nil)
    }

    @Test func `closing without a change does nothing`() {
        var followUp = LiveTVSheetFollowUp<String>()

        let closed = followUp.sheetClosed()

        #expect(closed.playback == nil)
        #expect(!closed.refreshes)
    }
}
