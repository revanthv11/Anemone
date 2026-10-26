import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// Wholphin's series page (`SeriesDetails`): title or logo, details, studios, genres and
/// overview, actions, then the seasons, the cast and crew, and similar series.
struct SeriesPage: View {
    @Binding var series: ItemDetails

    @Environment(BrowseModel.self) private var browse
    @FocusState private var focus: ItemFocus?
    @State private var memory = RowMemory()
    @State private var seasons: [ItemDetails] = []
    @State private var similar: [ItemDetails] = []
    @State private var alert: ItemAlert?
    @State private var confirmsPlayed = false

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: ItemLayout.sectionSpacing) {
                    header
                    buttons
                    rows
                }
                .padding(.horizontal, ItemLayout.horizontalInset)
                .padding(.top, ItemLayout.topInset)
                .padding(.bottom, ItemLayout.focusPadding)
                // Scrolling here shows the header with its top margin.
                .id(ItemLayout.headerID)
            }
            .onChange(of: focus) { _, focus in
                memory.note(focus)
                if focus?.isInHeader == true {
                    withAnimation { scroller.scrollTo(ItemLayout.headerID, anchor: .top) }
                }
            }
        }
        .background {
            BackdropImage(url: browse.imageURL(series.item.backdropImage, width: ItemLayout.backdropPixelWidth))
                .ignoresSafeArea()
        }
        .initialFocus($focus, .action(.play))
        .itemAlert($alert)
        // Marking a whole series is confirmed first, as in Wholphin.
        .alert(series.item.name, isPresented: $confirmsPlayed) {
            Button(series.userState.isPlayed ? "Mark as unwatched" : "Mark as watched") {
                Task { await setSeriesPlayed(!series.userState.isPlayed) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(series.userState.isPlayed
                ? "Mark the entire series as unwatched?"
                : "Mark the entire series as watched?")
        }
        // Seasons reload when the page comes back into view, as Wholphin refreshes them on resume.
        .task(id: series.id) {
            let session = browse.session
            let id = series.id
            // Similar series don't change between visits, so they're asked for once, as on the
            // movie page.
            let needsSimilar = similar.isEmpty
            async let seasons = attempt { try await session.seasons(ofSeries: id) }
            async let similar = needsSimilar ? attempt { try await session.similarItems(to: id) } : .success([])
            if let seasons = await browse.optional(seasons) {
                self.seasons = seasons
            }
            if needsSimilar, let similar = await browse.optional(similar) {
                self.similar = similar
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            ItemTitle(title: series.item.name, logo: series.logo)
            QuickDetails(details: series)
            if !series.studios.isEmpty {
                NameList(names: series.studios)
            }
            if !series.genres.isEmpty {
                NameList(names: series.genres)
            }
            if let overview = series.item.overview {
                OverviewButton(title: series.item.name, overview: overview)
                    .focused($focus, equals: .overview)
            }
        }
        .frame(maxWidth: ItemLayout.textWidth, alignment: .leading)
    }

    private var buttons: some View {
        HStack(spacing: 24) {
            // Wholphin plays the next episode up, or the first one.
            ActionButton(title: "Play", systemImage: "play.fill") {
                alert = .playbackUnavailable(resumeAt: nil)
            }
            .focused($focus, equals: .action(.play))
            .accessibilityIdentifier("action.play")
            ActionButton(title: "Shuffle", systemImage: "shuffle") {
                alert = .playbackUnavailable(resumeAt: nil)
            }
            .focused($focus, equals: .action(.shuffle))
            PlayedButton(isPlayed: series.userState.isPlayed) {
                confirmsPlayed = true
            }
            .focused($focus, equals: .action(.played))
            FavoriteButton(isFavorite: series.userState.isFavorite) {
                Task { await setFavorite(!series.userState.isFavorite) }
            }
            .focused($focus, equals: .action(.favorite))
            PlaybackNotWiredNote()
                .padding(.leading, 16)
        }
        .padding(.vertical, 20)
        .focusSection()
    }

    @ViewBuilder
    private var rows: some View {
        if !seasons.isEmpty {
            ItemRow(
                id: "seasons",
                title: "Seasons (\(seasons.count))",
                items: seasons,
                shape: .poster,
                focus: $focus,
                memory: memory,
            )
        }
        if !series.people.isEmpty {
            PeopleRow(id: "people", title: "People", people: series.people, focus: $focus, memory: memory)
        }
        if !similar.isEmpty {
            ItemRow(
                id: "similar",
                title: "More Like This",
                items: similar,
                shape: .poster,
                focus: $focus,
                memory: memory,
            )
        }
    }

    private func setFavorite(_ isFavorite: Bool) async {
        if let state = await browse.save(.favorite(isFavorite), for: series, failed: { alert = $0 }) {
            series.apply(state)
        }
    }

    /// Marks every episode, then reloads the series and its seasons for their new counts, like
    /// Wholphin's `setWatchedSeries`.
    private func setSeriesPlayed(_ isPlayed: Bool) async {
        guard await browse.save(.played(isPlayed), for: series, failed: { alert = $0 }) != nil else { return }
        let session = browse.session
        let id = series.id
        async let series = attempt { try await session.itemDetails(id: id) }
        async let seasons = attempt { try await session.seasons(ofSeries: id) }
        if let series = await browse.optional(series) {
            self.series = series
        }
        if let seasons = await browse.optional(seasons) {
            self.seasons = seasons
        }
    }
}
