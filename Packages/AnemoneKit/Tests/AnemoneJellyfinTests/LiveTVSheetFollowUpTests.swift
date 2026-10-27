@testable import AnemoneJellyfin
import Testing

/// What waits for a programme's details to close: on Home, the refresh after a recording changed
/// mustn't run while the sheet is up, since it can take the card showing the sheet out of its row.
struct LiveTVSheetFollowUpTests {
    @Test func `a recording changed refreshes once the sheet has closed, and only once`() {
        var followUp = LiveTVSheetFollowUp<String>()
        followUp.sheetOpened()

        let refreshesNow = followUp.recordingChanged()
        let whileOpen = followUp.refreshes
        let closed = followUp.sheetClosed()
        let closedAgain = followUp.sheetClosed()

        // Nothing runs until the sheet says it closed.
        #expect(!refreshesNow)
        #expect(whileOpen)
        #expect(closed.refreshes)
        #expect(closed.playback == nil)
        #expect(!closedAgain.refreshes)
    }

    @Test func `a change that lands after Menu closed the sheet refreshes at once`() {
        var followUp = LiveTVSheetFollowUp<String>()
        followUp.sheetOpened()

        // SwiftUI runs the sheet's onDismiss before Record or Cancel comes back.
        let closed = followUp.sheetClosed()
        let refreshesNow = followUp.recordingChanged()
        followUp.sheetOpened()
        let nextClosed = followUp.sheetClosed()

        #expect(!closed.refreshes)
        #expect(refreshesNow)
        // Not left for the next sheet to close.
        #expect(!nextClosed.refreshes)
    }

    @Test func `a change that lands while another sheet is up waits for that one`() {
        var followUp = LiveTVSheetFollowUp<String>()
        followUp.sheetOpened()
        _ = followUp.sheetClosed()
        followUp.sheetOpened()

        let refreshesNow = followUp.recordingChanged()
        let closed = followUp.sheetClosed()

        #expect(!refreshesNow)
        #expect(closed.refreshes)
    }

    @Test func `watch live plays once the sheet has closed`() {
        var followUp = LiveTVSheetFollowUp<String>()
        followUp.sheetOpened()

        followUp.play("channel 1")
        let closed = followUp.sheetClosed()
        let closedAgain = followUp.sheetClosed()

        #expect(closed.playback == "channel 1")
        #expect(!closed.refreshes)
        #expect(closedAgain.playback == nil)
    }

    @Test func `closing without a change does nothing`() {
        var followUp = LiveTVSheetFollowUp<String>()
        followUp.sheetOpened()

        let closed = followUp.sheetClosed()

        #expect(closed.playback == nil)
        #expect(!closed.refreshes)
        #expect(!followUp.isSheetOpen)
    }
}
