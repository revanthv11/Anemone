import AnemoneJellyfin
import AnemonePlayback
import SwiftUI

/// A card on Home's Channels or Watch Live row. A channel plays, as Wholphin's
/// `BaseItem.destination()` sends it straight to playback; a programme opens its details
/// (`ProgramDialog`), as Wholphin's search does, to watch its channel or record it.
struct LiveTVHomeCard<Label: View>: View {
    let item: MediaItem
    let isChannel: Bool
    let label: Label

    @Environment(BrowseModel.self) private var browse
    /// The signed-in app's card actions, whose player outlives Home's rows refreshing.
    @Environment(ItemContextActions.self) private var actions
    @State private var shownProgram: LiveTVProgram?
    /// The player, and Home's refresh, wait for the programme sheet to close: the refresh can take
    /// this card out of its row, sheet and all.
    @State private var followUp = LiveTVSheetFollowUp<PlaybackRequest>()

    init(item: MediaItem, isChannel: Bool, @ViewBuilder label: () -> Label) {
        self.item = item
        self.isChannel = isChannel
        self.label = label()
    }

    var body: some View {
        Button(action: select) {
            label
        }
        .sheet(item: $shownProgram, onDismiss: sheetDismissed) { program in
            LiveTVProgramSheet(program: program) { program in
                followUp.play(browse.playback(onChannelOf: program))
                shownProgram = nil
            } changed: { _, _ in
                // Active Recordings may have changed.
                followUp.recordingChanged()
            }
        }
    }

    private func select() {
        guard !isChannel else {
            actions.playback = browse.playback(of: LiveTVChannel(id: item.id, name: item.name))
            return
        }
        Task {
            do {
                shownProgram = try await browse.session.liveTVProgram(id: item.id)
            } catch {
                if let message = browse.problem(with: error, failure: "Couldn't load \(item.name).") {
                    actions.alert = .failed(message)
                }
            }
        }
    }

    private func sheetDismissed() {
        let next = followUp.sheetClosed()
        if let playback = next.playback {
            actions.playback = playback
        }
        if next.refreshes {
            Task { await browse.refresh() }
        }
    }
}
