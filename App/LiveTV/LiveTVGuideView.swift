import AnemoneCore
import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// Wholphin's TV guide (`TvGuideGrid`): channels down the side, 48 hours across, and the focused
/// programme's details above.
///
/// The rows scroll up and down as focus moves, like any tvOS list. Across, the guide shows a
/// window of a few hours that moves as focus leaves its edges: right from the last programme
/// showing, or left from the first while the guide is ahead of now. Left from the first programme
/// at now reaches the channel, as in Wholphin. Back returns to now, then to the first channel.
struct LiveTVGuideView: View {
    let model: LiveTVGuideModel
    /// Whether to move focus into the guide once it has loaded: only when the page opens.
    @Binding var takesFocus: Bool
    let logoURL: (LiveTVChannel) -> URL?
    /// A programme was selected: its details, or watching its channel for an empty stretch
    /// airing now.
    let selectProgram: (LiveTVProgram) -> Void
    let selectChannel: (LiveTVChannel) -> Void
    /// Wholphin's view options, from a button above the channels as in its guide.
    let showOptions: () -> Void

    enum Focus: Hashable {
        case channel(LiveTVChannel.ID)
        case program(LiveTVChannel.ID, LiveTVProgram.ID)

        var channelID: LiveTVChannel.ID {
            switch self {
            case let .channel(id), let .program(id, _): id
            }
        }
    }

    @AppStorage(Preferences.liveTVShowsDetails) private var showsDetails
    @AppStorage(Preferences.liveTVColorCodesPrograms) private var colorCodes
    @FocusState private var focus: Focus?
    @State private var focusedProgram: LiveTVProgram?

    var body: some View {
        GeometryReader { geometry in
            let stripWidth = max(geometry.size.width - LiveTVLayout.channelWidth - LiveTVLayout.columnSpacing, 1)
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: 12) {
                    if showsDetails {
                        LiveTVGuideHeader(program: focusedProgram)
                    }
                    HStack(alignment: .bottom, spacing: LiveTVLayout.columnSpacing) {
                        Button(action: showOptions) {
                            Label("View Options", systemImage: "slider.horizontal.3")
                                .font(.caption)
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(GuideCellStyle(fill: .clear))
                        .frame(width: LiveTVLayout.channelWidth, alignment: .leading)
                        .accessibilityIdentifier("livetv.viewOptions")
                        LiveTVTimeRuler(guide: model.guide, window: model.window, width: stripWidth)
                    }
                    rows(stripWidth: stripWidth)
                }
                .onExitCommand(perform: canGoBack ? { goBack(proxy) } : nil)
            }
        }
        .onMoveCommand(perform: moved)
        .onChange(of: focus) { old, new in
            focusChanged(from: old, to: new)
        }
        .task(id: model.state) {
            placeInitialFocus()
        }
    }

    private func rows(stripWidth: CGFloat) -> some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: LiveTVLayout.rowSpacing) {
                ForEach(Array(model.channels.enumerated()), id: \.element.id) { index, channel in
                    row(channel, stripWidth: stripWidth)
                        .id(channel.id)
                        .onAppear {
                            model.loadListings(forRow: index)
                        }
                }
            }
            .padding(.bottom, 40)
        }
        .scrollClipDisabled()
        .overlay(alignment: .topLeading) {
            nowLine(stripWidth: stripWidth)
        }
    }

    private func row(_ channel: LiveTVChannel, stripWidth: CGFloat) -> some View {
        HStack(spacing: LiveTVLayout.columnSpacing) {
            LiveTVChannelCell(channel: channel, logoURL: logoURL(channel)) {
                selectChannel(channel)
            }
            .frame(width: LiveTVLayout.channelWidth, height: LiveTVLayout.rowHeight)
            .focused($focus, equals: .channel(channel.id))
            HStack(spacing: 0) {
                if model.rows[channel.id] != nil {
                    ForEach(model.cells(on: channel.id)) { cell in
                        LiveTVProgramCell(cell: cell, colorCodes: colorCodes) {
                            selectProgram(cell.program)
                        }
                        .frame(width: CGFloat(cell.length / model.window.duration) * stripWidth)
                        .focused($focus, equals: .program(channel.id, cell.program.id))
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: stripWidth, height: LiveTVLayout.rowHeight, alignment: .leading)
        }
    }

    /// Wholphin's current-time marker, moved along once a minute.
    private func nowLine(stripWidth: CGFloat) -> some View {
        TimelineView(.everyMinute) { context in
            let window = model.window
            if window.contains(context.date) {
                Rectangle()
                    .fill(.tint)
                    .frame(width: 3)
                    .offset(
                        x: LiveTVLayout.channelWidth + LiveTVLayout.columnSpacing
                            + CGFloat(context.date.timeIntervalSince(window.start) / window.duration) * stripWidth,
                    )
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: Focus

    private func placeInitialFocus() {
        guard takesFocus, model.state == .loaded, let first = model.channels.first else { return }
        takesFocus = false
        if let program = model.currentProgram(on: first.id) {
            focus = .program(first.id, program.id)
        } else {
            focus = .channel(first.id)
        }
    }

    private func focusChanged(from old: Focus?, to new: Focus?) {
        // Left from the first programme showing lands on the channel; while the guide is ahead of
        // now, the guide moves back instead.
        if case let .channel(channelID) = new, case let .program(oldChannel, programID) = old,
           oldChannel == channelID, let program = model.program(programID, on: channelID),
           let previous = model.moveBack(from: program)
        {
            refocus(.program(channelID, previous.id))
            return
        }
        if case let .program(channelID, programID) = new {
            focusedProgram = model.program(programID, on: channelID)
        }
    }

    /// Right from the last programme showing moves the guide on. Focus can't move there, so this
    /// is the only thing the press does.
    private func moved(_ direction: MoveCommandDirection) {
        guard direction == .right, case let .program(channelID, programID) = focus,
              let program = model.program(programID, on: channelID),
              let next = model.moveForward(from: program)
        else { return }
        refocus(.program(channelID, next.id))
    }

    /// Focuses a programme once the window has moved to show it.
    private func refocus(_ target: Focus) {
        Task { @MainActor in
            focus = target
        }
    }

    // MARK: Back

    private var canGoBack: Bool {
        guard let focus else { return false }
        return !isOnNow(focus) || model.channels.first?.id != focus.channelID
    }

    private func isOnNow(_ focus: Focus) -> Bool {
        guard case let .program(channelID, programID) = focus else { return true }
        return model.window.start == model.guide.start && model.currentProgram(on: channelID)?.id == programID
    }

    /// Wholphin's Back in the guide: to what's on now in the row, then to the first channel.
    private func goBack(_ proxy: ScrollViewProxy) {
        guard let focus else { return }
        if !isOnNow(focus) {
            model.showNow()
            if let current = model.currentProgram(on: focus.channelID) {
                refocus(.program(focus.channelID, current.id))
            }
        } else if let first = model.channels.first {
            withAnimation {
                proxy.scrollTo(first.id, anchor: .top)
            }
            if let current = model.currentProgram(on: first.id) {
                refocus(.program(first.id, current.id))
            }
        }
    }
}
