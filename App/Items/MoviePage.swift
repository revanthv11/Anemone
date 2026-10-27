import AnemoneJellyfin
import AnemonePlayback
import AnemoneUI
import SwiftUI

/// Wholphin's movie page (`MovieDetails`): title or logo, details, overview and actions, then
/// the cast and crew and similar items. Videos and other types without a page of their own use
/// it too, and so do episodes outside a season, which get Wholphin's `EpisodeDetails` header
/// and only their chapters below it.
struct MoviePage: View {
    @Binding var item: ItemDetails

    @Environment(BrowseModel.self) private var browse
    @Environment(\.theme) private var theme
    @FocusState private var focus: ItemFocus?
    @State private var memory = RowMemory()
    @State private var similar: [ItemDetails] = []
    @State private var alert: ItemAlert?
    @State private var playback: PlaybackRequest?
    @State private var extras = ItemExtras()
    @State private var playsSong = false

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: ItemLayout.sectionSpacing) {
                    header
                    buttons
                    if isEpisode {
                        // Wholphin's episode page has no rows, but its chapters show here as they
                        // do for episodes on the season page.
                        ChaptersRow(chapters: extras.chapters, focus: $focus, memory: memory, play: play(from:))
                    } else {
                        rows
                    }
                }
                .padding(.horizontal, ItemLayout.horizontalInset)
                .padding(.top, ItemLayout.topInset)
                .padding(.bottom, ItemLayout.focusPadding)
                // Scrolling here shows the header with its top margin.
                .id(ItemLayout.headerID)
            }
            .onChange(of: focus) { _, focus in
                memory.note(focus)
                // Like Wholphin's `bringIntoView`: the whole header shows with its buttons.
                if focus?.isInHeader == true {
                    withAnimation { scroller.scrollTo(ItemLayout.headerID, anchor: .top) }
                }
            }
        }
        .background {
            BackdropImage(url: browse.imageURL(item.item.backdropImage, width: ItemLayout.backdropPixelWidth))
                .ignoresSafeArea()
        }
        .initialFocus($focus, item.isPlayable ? .action(.play) : .action(.played))
        .itemAlert($alert)
        .player($playback) {
            await reload()
        }
        .itemExtras($extras, of: item.id)
        .songPlayback(item, isRequested: $playsSong)
        .task(id: item.id) {
            guard !isEpisode, similar.isEmpty else { return }
            let session = browse.session
            let id = item.id
            similar = await browse.optional(attempt { try await session.similarItems(to: id) }) ?? []
        }
    }

    private var isEpisode: Bool {
        item.item.kind == .episode
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isEpisode {
                // Wholphin's `EpisodeDetailsHeader`: the series, then the episode.
                Text(item.item.episode?.seriesName ?? "")
                    .font(.title.bold())
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("detail.title")
                Text(item.item.name)
                    .font(.title3)
                    .lineLimit(1)
            } else {
                ItemTitle(title: item.item.name, logo: item.logo)
            }
            QuickDetails(details: item)
            if !item.genres.isEmpty {
                NameList(names: item.genres)
            }
            if let tagline = item.tagline {
                Text(tagline)
                    .font(.callout)
                    .italic()
            }
            if let overview = item.item.overview {
                OverviewButton(title: item.item.name, overview: overview)
                    .focused($focus, equals: .overview)
            }
            if !item.directors.isEmpty {
                Text("Directed by \(item.directors.joined(separator: ", "))")
                    .font(.callout)
            }
        }
        .foregroundStyle(theme.onBackground)
        .frame(maxWidth: ItemLayout.textWidth, alignment: .leading)
    }

    private var buttons: some View {
        HStack(spacing: 24) {
            if item.isPlayable {
                PlaybackButtons(resumePosition: item.userState.resumePosition, focus: $focus, play: play(from:))
            }
            PlayedButton(isPlayed: item.userState.isPlayed) {
                Task { await save(.played(!item.userState.isPlayed)) }
            }
            .focused($focus, equals: .action(.played))
            FavoriteButton(isFavorite: item.userState.isFavorite) {
                Task { await save(.favorite(!item.userState.isFavorite)) }
            }
            .focused($focus, equals: .action(.favorite))
            TrailerButton(trailers: extras.trailers).focused($focus, equals: .action(.trailer))
            DeleteButton(item: item, canDelete: extras.canDelete).focused($focus, equals: .action(.delete))
            VersionPicker(item: item)
        }
        .padding(.vertical, 20)
        .focusSection()
    }

    @ViewBuilder
    private var rows: some View {
        if !item.people.isEmpty {
            PeopleRow(id: "people", title: "People", people: item.people, focus: $focus, memory: memory)
        }
        ChaptersRow(chapters: extras.chapters, focus: $focus, memory: memory, play: play(from:))
        ExtrasRow(extras: $extras, focus: $focus, memory: memory)
        if !similar.isEmpty {
            // Wholphin shows posters only when the page is a movie's.
            ItemRow(
                id: "similar",
                title: "More Like This",
                items: similar,
                shape: item.item.kind == .movie ? .poster : .thumb,
                focus: $focus,
                memory: memory,
            )
        }
        SeerrItemRow(item: item, focus: $focus, memory: memory)
    }

    private func play(from position: Duration?) {
        if item.item.kind == .audio {
            playsSong = true
        } else {
            playback = browse.playback(of: item, from: position)
        }
    }

    /// After playback, picks up the new resume position, or the item marked watched. A failed
    /// reload keeps what's showing.
    private func reload() async {
        let session = browse.session
        let id = item.id
        if let details = await browse.optional(attempt { try await session.itemDetails(id: id) }) {
            item = details
        }
    }

    private func save(_ change: UserStateChange) async {
        if let state = await browse.save(change, for: item, failed: { alert = $0 }) {
            item.apply(state)
        }
    }
}
