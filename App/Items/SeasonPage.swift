import AnemoneJellyfin
import AnemonePlayback
import AnemoneUI
import SwiftUI

/// Wholphin's series overview (`SeriesOverview`), opened from a season or an episode: a tab for
/// each season, the series' title or logo, the selected episode's details over the season's
/// episodes, actions for that episode, and its cast and guest stars.
struct SeasonPage: View {
    let seriesID: MediaItem.ID
    let seasonID: MediaItem.ID
    /// The episode to start on; the season's first when `nil`.
    let episodeID: MediaItem.ID?

    @Environment(BrowseModel.self) private var browse
    @FocusState private var focus: ItemFocus?
    @State private var memory = RowMemory()
    @State private var alert: ItemAlert?
    @State private var playback: PlaybackController?

    @State private var series: ItemDetails?
    @State private var seasons: [ItemDetails] = []
    @State private var problem: String?
    /// The season picked from the tabs; `seasonID` until one is.
    @State private var pickedSeasonID: MediaItem.ID?
    /// The season `episodes` belong to.
    @State private var episodesSeasonID: MediaItem.ID?
    /// `nil` while they load.
    @State private var episodes: [ItemDetails]?
    @State private var episodesProblem: String?
    /// The episode the details and actions are for: the last one focused.
    @State private var selectedEpisodeID: MediaItem.ID?
    @State private var episodeScroll: MediaItem.ID?
    /// Set when a season is picked, so focus moves to its first episode once it loads.
    @State private var focusesEpisodes = false

    private static let episodeRow = "episodes"

    var body: some View {
        Group {
            if let series {
                content(series)
            } else if let problem {
                PageMessage(message: problem)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background {
            BackdropImage(url: browse.imageURL(series?.item.backdropImage, width: ItemLayout.backdropPixelWidth))
                .ignoresSafeArea()
        }
        // Wholphin starts on the episode that opened the page.
        .initialFocus($focus, series == nil ? nil : selectedEpisodeID.map(episodeFocus))
        .itemAlert($alert)
        .player($playback) {
            await loadEpisodes(of: currentSeasonID)
        }
        .task {
            await loadSeries()
        }
        .task(id: currentSeasonID) {
            await loadEpisodes(of: currentSeasonID)
        }
        .onChange(of: focus) { _, focus in
            memory.note(focus)
            if case let .card(row, item) = focus, row == Self.episodeRow {
                selectedEpisodeID = item
            }
        }
    }

    private var currentSeasonID: MediaItem.ID {
        pickedSeasonID ?? seasonID
    }

    private var selectedEpisode: ItemDetails? {
        episodes?.first { $0.id == selectedEpisodeID }
    }

    private func episodeFocus(_ id: MediaItem.ID) -> ItemFocus {
        .card(row: Self.episodeRow, item: id)
    }

    private func content(_ series: ItemDetails) -> some View {
        ScrollViewReader { scroller in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: ItemLayout.sectionSpacing) {
                    // Wholphin keeps this part in view together while it has focus.
                    VStack(alignment: .leading, spacing: 12) {
                        seasonTabs
                        ItemTitle(title: series.item.name, logo: series.logo)
                        episodeHeader
                        episodeRow
                        episodeButtons
                    }
                    peopleRows
                }
                .padding(.horizontal, ItemLayout.horizontalInset)
                .padding(.top, 40)
                .padding(.bottom, ItemLayout.focusPadding)
                // Scrolling here shows the header with its top margin.
                .id(ItemLayout.headerID)
            }
            .onChange(of: focus) { _, focus in
                if focus?.isInHeader == true || isEpisodeRowFocused {
                    withAnimation { scroller.scrollTo(ItemLayout.headerID, anchor: .top) }
                }
            }
        }
    }

    private var seasonTabs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 16) {
                ForEach(seasons) { season in
                    Button(season.item.name) {
                        pick(season)
                    }
                    .buttonStyle(SeasonTabStyle(isSelected: season.id == currentSeasonID))
                    .focused($focus, equals: .tab(season.id))
                    .accessibilityIdentifier("tab.\(season.id)")
                    .accessibilityAddTraits(season.id == currentSeasonID ? .isSelected : [])
                }
            }
            .padding(.vertical, 20)
        }
        .scrollClipDisabled()
        .focusSection()
        // Entering the tabs lands on the season being shown.
        .defaultFocus($focus, .tab(currentSeasonID), priority: .userInitiated)
    }

    /// Wholphin's `FocusedEpisodeHeader`.
    private var episodeHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(selectedEpisode?.item.name ?? " ")
                .font(.title3.bold())
                .lineLimit(1)
                .accessibilityIdentifier("episode.title")
            if let selectedEpisode {
                QuickDetails(details: selectedEpisode)
            } else {
                Text(" ")
                    .font(.callout)
            }
            OverviewButton(title: selectedEpisode?.item.name ?? "", overview: selectedEpisode?.item.overview ?? "")
                .focused($focus, equals: .overview)
                .disabled(selectedEpisode?.item.overview == nil)
        }
        .frame(maxWidth: ItemLayout.textWidth, alignment: .leading)
        .animation(nil, value: selectedEpisodeID)
    }

    @ViewBuilder
    private var episodeRow: some View {
        if let episodes {
            CardRow(
                id: Self.episodeRow,
                title: nil,
                elements: episodes,
                focus: $focus,
                memory: memory,
                scrollPosition: $episodeScroll,
            ) { episode in
                // Wholphin plays an episode when it's selected, resuming where it was left.
                Button {
                    playback = browse.playback(of: episode, from: episode.userState.resumePosition)
                } label: {
                    ItemCard(details: episode, shape: .thumb, title: episode.item.name, subtitle: episode.numberText)
                }
                .buttonStyle(.borderless)
                // While focus is elsewhere on the page, the selected episode stands out.
                .opacity(focus != nil && !isEpisodeRowFocused && episode.id != selectedEpisodeID ? 0.4 : 1)
                .animation(.easeOut(duration: 0.2), value: isEpisodeRowFocused)
            }
            .overlay {
                if episodes.isEmpty {
                    Text("This season has no episodes.")
                        .foregroundStyle(.secondary)
                }
            }
        } else if let episodesProblem {
            NoticeText(episodesProblem)
                .frame(height: ItemLayout.episodeRowHeight)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
                .frame(height: ItemLayout.episodeRowHeight)
        }
    }

    /// Wholphin's `FocusedEpisodeFooter`.
    private var episodeButtons: some View {
        HStack(spacing: 24) {
            if let episode = selectedEpisode {
                PlaybackButtons(resumePosition: episode.userState.resumePosition, focus: $focus) { position in
                    playback = browse.playback(of: episode, from: position)
                }
                PlayedButton(isPlayed: episode.userState.isPlayed) {
                    Task {
                        // Wholphin goes back to the episodes, ready for the next one. After a
                        // failure, focus stays put behind the error.
                        if await save(.played(!episode.userState.isPlayed), for: episode) {
                            focus = episodeFocus(episode.id)
                        }
                    }
                }
                .focused($focus, equals: .action(.played))
                FavoriteButton(isFavorite: episode.userState.isFavorite) {
                    Task { await save(.favorite(!episode.userState.isFavorite), for: episode) }
                }
                .focused($focus, equals: .action(.favorite))
            }
        }
        .frame(minHeight: 80)
        .focusSection()
    }

    @ViewBuilder
    private var peopleRows: some View {
        let people = selectedEpisode?.people ?? []
        let guestStars = people.filter { $0.kind == .guestStar }
        let castAndCrew = people.filter { $0.kind != .guestStar }
        if !castAndCrew.isEmpty {
            PeopleRow(id: "cast", title: "Cast & Crew", people: castAndCrew, focus: $focus, memory: memory)
        }
        if !guestStars.isEmpty {
            PeopleRow(id: "guests", title: "Guest Stars", people: guestStars, focus: $focus, memory: memory)
        }
    }

    private var isEpisodeRowFocused: Bool {
        if case let .card(row, _) = focus {
            return row == Self.episodeRow
        }
        return false
    }

    private func pick(_ season: ItemDetails) {
        if season.id == currentSeasonID {
            if let selectedEpisodeID {
                focus = episodeFocus(selectedEpisodeID)
            }
        } else {
            focusesEpisodes = true
            pickedSeasonID = season.id
        }
    }
}

/// Loading and saving.
private extension SeasonPage {
    /// Runs again whenever the page comes back into view, like Wholphin's refresh on resume. A
    /// failed refresh keeps what's showing.
    func loadSeries() async {
        let session = browse.session
        let seriesID = seriesID
        async let series = attempt { try await session.itemDetails(id: seriesID) }
        async let seasons = attempt { try await session.seasons(ofSeries: seriesID) }
        switch await series {
        case let .success(series):
            self.series = series
        case let .failure(error):
            let message = browse.problem(with: error, doing: "load this series from \(browse.server.name)")
            if self.series == nil {
                problem = message
            }
        }
        if let seasons = await browse.optional(seasons) {
            self.seasons = seasons
        }
    }

    func loadEpisodes(of seasonID: MediaItem.ID) async {
        // Coming back to the page refreshes the season in place, keeping the selected episode.
        let isRefresh = episodesSeasonID == seasonID
        let isFirstSeason = episodesSeasonID == nil
        if !isRefresh {
            episodes = nil
            episodesProblem = nil
        }
        do {
            let loaded = try await browse.session.episodes(ofSeries: seriesID, season: seasonID)
            guard !isRefresh else {
                episodes = loaded
                return
            }
            // The first season shown starts on the episode that opened the page; others start
            // at their first episode.
            let start = isFirstSeason ? loaded.index(ofID: episodeID, number: nil) : 0
            let selected = loaded.indices.contains(start) ? loaded[start].id : nil
            episodes = loaded
            episodesSeasonID = seasonID
            selectedEpisodeID = selected
            episodeScroll = selected
            if focusesEpisodes, let selected {
                focusesEpisodes = false
                focus = episodeFocus(selected)
            }
        } catch {
            let message = browse.problem(with: error, doing: "load this season's episodes")
            if !isRefresh {
                episodesProblem = message
            }
        }
    }

    /// Returns whether the server saved the change.
    @discardableResult
    func save(_ change: UserStateChange, for episode: ItemDetails) async -> Bool {
        guard let state = await browse.save(change, for: episode, failed: { alert = $0 }) else { return false }
        if let index = episodes?.firstIndex(where: { $0.id == episode.id }) {
            episodes?[index].apply(state)
        }
        return true
    }
}

/// A season tab: highlighted when focused, and marked while its season is shown.
private struct SeasonTabStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        TabBody(configuration: configuration, isSelected: isSelected)
    }

    private struct TabBody: View {
        let configuration: ButtonStyleConfiguration
        let isSelected: Bool
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .font(.callout.weight(isSelected ? .bold : .regular))
                .foregroundStyle(isFocused ? Color.black : isSelected ? .white : .white.opacity(0.6))
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background(
                    isFocused ? Color.white : isSelected ? .white.opacity(0.2) : .clear,
                    in: .capsule,
                )
                .scaleEffect(isFocused ? 1.08 : configuration.isPressed ? 0.98 : 1)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}

private extension ItemDetails {
    /// What Wholphin puts in an episode card's corner: "E3", or the air date.
    var numberText: String? {
        item.episode?.episodeNumber.map { "E\($0)" } ?? premiereDate?.dayText
    }
}

extension ItemLayout {
    /// A thumb card with its caption and focus room, held while episodes load.
    static let episodeRowHeight: CGFloat = CardShape.thumb.cardWidth / CardShape.thumb.aspectRatio + 120
}
