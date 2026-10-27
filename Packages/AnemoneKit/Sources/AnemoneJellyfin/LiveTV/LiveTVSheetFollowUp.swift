import Foundation

/// What waits for a programme's details sheet to close: the player for Watch Live, which can't
/// open over the sheet, and a refresh after a recording was set or cancelled, which on Home can
/// take the card showing the sheet out of its row while the sheet is still up.
public struct LiveTVSheetFollowUp<Playback: Sendable>: Sendable {
    public private(set) var playback: Playback?
    public private(set) var refreshes = false

    public init() {}

    /// Watch Live was chosen: plays once the sheet has closed.
    public mutating func play(_ playback: Playback) {
        self.playback = playback
    }

    /// A recording was set or cancelled: refreshes once the sheet has closed.
    public mutating func recordingChanged() {
        refreshes = true
    }

    /// The sheet closed: what to do now, once.
    public mutating func sheetClosed() -> (playback: Playback?, refreshes: Bool) {
        defer { self = Self() }
        return (playback, refreshes)
    }
}
