import AnemoneJellyfin
import AnemonePlayback
import AnemoneUI
import SwiftUI

/// A Live TV library, ported from Wholphin's `CollectionFolderLiveTv`: tabs for the guide, the
/// channels, the DVR schedule, then each folder of recordings.
struct LiveTVLibraryView: View {
    let library: Library
    @Binding var path: NavigationPath

    enum Tab: Hashable {
        case guide
        case channels
        case schedule
        case recordings(Library)

        var title: String {
            switch self {
            case .guide: String(localized: "Guide")
            case .channels: String(localized: "Channels")
            case .schedule: String(localized: "Schedule")
            case let .recordings(folder): folder.name
            }
        }

        var identifier: String {
            switch self {
            case .guide: "livetv.tab.guide"
            case .channels: "livetv.tab.channels"
            case .schedule: "livetv.tab.schedule"
            case let .recordings(folder): "livetv.tab.\(folder.id)"
            }
        }
    }

    @Environment(BrowseModel.self) private var browse
    @State private var tab = Tab.guide
    @State private var folders: [Library] = []
    @State private var guide: LiveTVGuideModel?
    /// Whether the guide still moves focus into itself once loaded: only when the page opens.
    @State private var guideTakesFocus = true
    /// Bumped when recordings change, so the schedule and channels load again.
    @State private var version = 0
    @State private var shownProgram: LiveTVProgram?
    @State private var shownChannel: LiveTVChannel?
    @State private var seriesToCancel: LiveTVSeriesTimer?
    /// Waits for the programme sheet to close before the player opens.
    @State private var pendingPlayback: PlaybackRequest?
    @State private var playback: PlaybackRequest?
    @State private var notice: String?
    @State private var showsViewOptions = false
    @FocusState private var focusedTab: Tab?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            tabBar
                .padding(.horizontal, LiveTVLayout.horizontalInset)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .overlay(alignment: .bottom) {
            if let notice {
                NoticeText(notice)
                    .padding(.bottom, 40)
                    .task {
                        try? await Task.sleep(for: .seconds(4))
                        self.notice = nil
                    }
            }
        }
        // Again when the app comes back to the foreground, so the guide starts from now.
        .pageTask(id: library.id) {
            await load()
        }
        .player($playback) {}
        .sheet(item: $shownProgram, onDismiss: playPending) { program in
            LiveTVProgramSheet(program: program) { program in
                pendingPlayback = browse.playback(onChannelOf: program, channel: guide?.channel(program.channelID))
                shownProgram = nil
            } changed: { program, series in
                recordingsChanged(onChannel: series ? nil : program.channelID)
            }
        }
        .sheet(isPresented: $showsViewOptions) {
            // The channel order may have changed.
            Task {
                version += 1
                await guide?.load()
            }
        } content: {
            LiveTVViewOptionsSheet()
        }
        .confirmationDialog(
            shownChannel?.title ?? "",
            isPresented: isPresented($shownChannel),
            titleVisibility: .visible,
            presenting: shownChannel,
        ) { channel in
            Button("Watch Live") {
                playback = browse.playback(of: channel)
            }
            Button(channel.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
                toggleFavorite(channel)
            }
        }
        .confirmationDialog(
            "Stop recording \(seriesToCancel?.name ?? "this series")?",
            isPresented: isPresented($seriesToCancel),
            titleVisibility: .visible,
            presenting: seriesToCancel,
        ) { series in
            Button("Cancel Series Recording", role: .destructive) {
                cancel(series)
            }
        }
    }

    private var tabs: [Tab] {
        [.guide, .channels, .schedule] + folders.map(Tab.recordings)
    }

    /// Wholphin's tab row: a tab shows as soon as it's focused, and moving up into the row lands
    /// on the tab showing.
    private var tabBar: some View {
        HStack(spacing: 16) {
            ForEach(tabs, id: \.self) { item in
                Button(item.title) {
                    tab = item
                }
                .buttonStyle(LiveTVTabStyle(isSelected: tab == item))
                .focused($focusedTab, equals: item)
                .accessibilityIdentifier(item.identifier)
                .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
        }
        .focusSection()
        .defaultFocus($focusedTab, tab, priority: .userInitiated)
        .onChange(of: focusedTab) { _, focused in
            if let focused {
                tab = focused
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .guide:
            guideContent
                .padding(.horizontal, LiveTVLayout.horizontalInset)
        case .channels:
            LiveTVChannelsView(version: version) { channel in
                playback = browse.playback(of: channel)
            } toggleFavorite: { channel in
                toggleFavorite(channel)
            }
            .padding(.horizontal, LiveTVLayout.horizontalInset)
        case .schedule:
            LiveTVScheduleView(version: version) { timer in
                shownProgram = timer.program
            } play: { recording in
                playback = browse.playback(of: recording)
            } cancel: { recording, series in
                cancel(recording, series: series)
            } cancelSeries: { series in
                seriesToCancel = series
            }
            .padding(.horizontal, LiveTVLayout.horizontalInset)
        case let .recordings(folder):
            // The library page brings its own margins, sort, filters and view options; the
            // folder's library lists its top level with the video sort options, as Wholphin does.
            LibraryScreen(library: folder, path: $path)
        }
    }

    @ViewBuilder
    private var guideContent: some View {
        switch guide?.state {
        case .loaded:
            if let guide {
                LiveTVGuideView(
                    model: guide,
                    takesFocus: $guideTakesFocus,
                    logoURL: { browse.imageURL($0.image, width: 300) },
                    selectProgram: select,
                    selectChannel: { shownChannel = $0 },
                    showOptions: { showsViewOptions = true },
                )
            }
        case .noChannels:
            PageMessage(message: String(localized: "Live TV is on, but \(browse.server.name) has no channels."))
        case let .failed(problem):
            VStack(spacing: 30) {
                PageMessage(message: problem)
                Button("Try again") {
                    Task { await guide?.load() }
                }
            }
        case .loading, nil:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func load() async {
        let guide = guide ?? LiveTVGuideModel(browse: browse)
        self.guide = guide
        async let folders = try? browse.session.liveTVRecordingFolders()
        await guide.load()
        self.folders = await folders ?? self.folders
    }

    /// Like Wholphin: a programme opens its details; an empty stretch of the guide airing now
    /// plays the channel, and one later says there's nothing listed.
    private func select(_ program: LiveTVProgram) {
        guard program.isPlaceholder else {
            shownProgram = program
            return
        }
        if program.isAiring(at: .now) {
            playback = browse.playback(onChannelOf: program, channel: guide?.channel(program.channelID))
        } else {
            notice = String(localized: "Nothing is listed for this time.")
        }
    }

    private func playPending() {
        if let pendingPlayback {
            self.pendingPlayback = nil
            playback = pendingPlayback
        }
    }

    /// The schedule and channels load again, and so do the guide's listings: for a programme's
    /// own recording, only the rows of its channel's page; for a series (`channel` `nil`), which
    /// can mark programmes on any channel, every row loaded so far.
    private func recordingsChanged(onChannel channel: LiveTVChannel.ID?) {
        version += 1
        Task {
            await guide?.reloadListings(channel: channel)
        }
    }

    private func toggleFavorite(_ channel: LiveTVChannel) {
        Task {
            do {
                _ = try await browse.session.setFavorite(!channel.isFavorite, itemID: channel.id)
                version += 1
                await guide?.load()
            } catch {
                notice = browse.problem(with: error, failure: "Couldn't update \(channel.name).")
            }
        }
    }

    private func cancel(_ series: LiveTVSeriesTimer) {
        cancelTimer(series.id, series: true, name: series.name, channel: nil)
    }

    private func cancel(_ recording: LiveTVRecording, series: Bool) {
        let program = recording.program
        guard let timerID = series ? program.seriesTimerID : program.timerID else { return }
        cancelTimer(timerID, series: series, name: program.name, channel: series ? nil : program.channelID)
    }

    private func cancelTimer(_ timerID: String, series: Bool, name: String, channel: LiveTVChannel.ID?) {
        Task {
            do {
                try await browse.session.cancelRecording(timerID: timerID, series: series)
                recordingsChanged(onChannel: channel)
            } catch {
                notice = browse.problem(with: error, failure: "Couldn't cancel \(name).")
            }
        }
    }

    private func isPresented(_ value: Binding<(some Any)?>) -> Binding<Bool> {
        Binding { value.wrappedValue != nil } set: { isShown in
            if !isShown {
                value.wrappedValue = nil
            }
        }
    }
}

/// A tab in the row at the top of the page: on the theme's light platter when focused, and
/// underlined in its accent when showing.
private struct LiveTVTabStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        TabLabel(label: configuration.label, isSelected: isSelected)
    }

    private struct TabLabel<Label: View>: View {
        let label: Label
        let isSelected: Bool

        @Environment(\.isFocused) private var isFocused
        @Environment(\.theme) private var theme

        private var textColor: ThemeColor {
            if isFocused {
                theme.onFocusedPlatter
            } else {
                isSelected ? theme.onBackground : theme.secondaryText
            }
        }

        var body: some View {
            label
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .foregroundStyle(textColor)
                .background(isFocused ? theme.focusedPlatter.color : .clear, in: .capsule)
                .overlay(alignment: .bottom) {
                    if isSelected, !isFocused {
                        Capsule().fill(theme.accent).frame(height: 3).padding(.horizontal, 24)
                    }
                }
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}
