import Foundation

/// What waits for a programme's details sheet to close: the player for Watch Live, which can't
/// open over the sheet, and a refresh after a recording was set or cancelled, which on Home can
/// take the card showing the sheet out of its row while the sheet is still up.
public struct LiveTVSheetFollowUp<Playback: Sendable>: Sendable {
    public private(set) var playback: Playback?
    public private(set) var refreshes = false
    /// Whether the sheet is up. Record and Cancel keep going when Menu closes the sheet first,
    /// and a change that lands after it closed has nothing left to wait for.
    public private(set) var isSheetOpen = false

    public init() {}

    /// The sheet opened: nothing waits for it yet.
    public mutating func sheetOpened() {
        self = Self()
        isSheetOpen = true
    }

    /// Watch Live was chosen: plays once the sheet has closed.
    public mutating func play(_ playback: Playback) {
        self.playback = playback
    }

    /// A recording was set or cancelled: refreshes once the sheet has closed. Returns `true` when
    /// it already has, so the caller refreshes now; otherwise the refresh would wait for the next
    /// sheet to close.
    public mutating func recordingChanged() -> Bool {
        guard isSheetOpen else { return true }
        refreshes = true
        return false
    }

    /// The sheet closed: what to do now, once.
    public mutating func sheetClosed() -> (playback: Playback?, refreshes: Bool) {
        defer { self = Self() }
        return (playback, refreshes)
    }
}
