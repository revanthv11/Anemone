import AnemoneJellyfin
import AnemonePlayback
import AnemoneUI
import SwiftUI

/// Wholphin's artist page (`ArtistDetailsPage`): the artist's picture beside their name,
/// details, genres and overview; Play, Shuffle, Instant Mix and favourite; their popular songs;
/// then rows of their albums, the albums they appear on, and similar artists.
struct ArtistPage: View {
    @Binding var details: ItemDetails

    @Environment(BrowseModel.self) private var browse
    @Environment(MusicPlayer.self) private var player
    @FocusState private var focus: MusicFocus?
    @State private var popular: [MusicItem] = []
    @State private var albums: [MusicItem] = []
    @State private var appearsOn: [MusicItem] = []
    @State private var similar: [MusicItem] = []
    @State private var alert: ItemAlert?
    @State private var showsNowPlaying = false
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: ItemLayout.sectionSpacing) {
                    MusicHeader(details: details, image: details.item.squareImage) {
                        HStack(spacing: 24) {
                            MusicActionButtons(
                                details: details,
                                artists: [],
                                focus: $focus,
                                play: play(shuffled:),
                                instantMix: {
                                    player.playInstantMix(from: details.id, browse: browse) { alert = .failed($0) }
                                    showsNowPlaying = true
                                },
                                favorite: { Task { await toggleFavorite() } },
                                nowPlaying: { showsNowPlaying = true },
                            )
                        }
                    }
                    .id(ItemLayout.headerID)
                    if !popular.isEmpty {
                        popularSongs
                    }
                    if !albums.isEmpty {
                        MusicRow(id: "albums", title: String(localized: "Albums"), items: albums, focus: $focus)
                    }
                    if !appearsOn.isEmpty {
                        MusicRow(
                            id: "appearsOn",
                            title: String(localized: "Appears On"),
                            items: appearsOn,
                            focus: $focus,
                        )
                    }
                    if !similar.isEmpty {
                        MusicRow(
                            id: "similar",
                            title: String(localized: "More Like This"),
                            items: similar,
                            focus: $focus,
                        )
                    }
                }
                .padding(.horizontal, ItemLayout.horizontalInset)
                .padding(.top, ItemLayout.topInset)
                .padding(.bottom, ItemLayout.focusPadding)
            }
            .onChange(of: focus) { _, focus in
                if focus?.isInHeader == true {
                    withAnimation { scroller.scrollTo(ItemLayout.headerID, anchor: .top) }
                }
            }
        }
        .background {
            BackdropImage(url: browse.imageURL(details.item.backdropImage, width: ItemLayout.backdropPixelWidth))
                .ignoresSafeArea()
        }
        .defaultFocus($focus, .action(.play))
        .itemAlert($alert)
        .nowPlaying(isPresented: $showsNowPlaying)
        .pageTask(id: details.id) {
            await load()
        }
    }

    /// Wholphin's "Popular Songs": each plays on its own.
    private var popularSongs: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Popular Songs")
                .font(.headline)
                .foregroundStyle(theme.onBackground)
                .padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(popular.enumerated()), id: \.element.id) { index, song in
                SongRow(song: song, number: index + 1) {
                    play(song)
                }
                .songMenu(song) { play(song) }
                .focused($focus, equals: .song(list: "popular", id: song.id))
                .accessibilityIdentifier("song.\(index)")
            }
        }
        .frame(maxWidth: ItemLayout.textWidth + 300)
        .focusSection()
    }

    private func play(shuffled: Bool) {
        player.play(.artist(details.id), shuffled: shuffled, browse: browse) { alert = .failed($0) }
        showsNowPlaying = true
    }

    private func play(_ song: MusicItem) {
        player.play([song])
        showsNowPlaying = true
    }

    private func load() async {
        let session = browse.session
        let id = details.id
        async let artist = attempt { try await session.musicItem(id: id) }
        async let topSongs = attempt { try await session.popularSongs(byArtist: id) }
        async let ownAlbums = attempt { try await session.albums(byArtist: id) }
        async let otherAlbums = attempt { try await session.albums(featuringArtist: id) }
        if let artist = await browse.optional(artist) {
            details = artist.details
        }
        // Each row is optional, as in Wholphin; a failed refresh keeps what's showing.
        popular = await browse.optional(topSongs) ?? popular
        albums = await browse.optional(ownAlbums) ?? albums
        appearsOn = await browse.optional(otherAlbums) ?? appearsOn
        if similar.isEmpty {
            similar = await browse.optional(attempt {
                try await session.similarMusic(to: id, excludingArtists: [id])
            }) ?? []
        }
    }

    private func toggleFavorite() async {
        if let state = await browse.save(
            .favorite(!details.userState.isFavorite),
            for: details,
            failed: { alert = $0 },
        ) {
            details.apply(state)
        }
    }
}
