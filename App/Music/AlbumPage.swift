import AnemoneJellyfin
import AnemonePlayback
import AnemoneUI
import SwiftUI

/// Wholphin's album page (`AlbumDetailsPage`): the cover beside the artist, title, details,
/// genres and overview; Play, Shuffle, Instant Mix and favourite; the songs; then similar
/// albums. Opened on a song, focus starts on it.
struct AlbumPage: View {
    @Binding var details: ItemDetails
    /// The song to focus first, when the page was opened from one.
    var focusedSongID: MediaItem.ID?

    @Environment(BrowseModel.self) private var browse
    @Environment(MusicPlayer.self) private var player
    @FocusState private var focus: MusicFocus?
    @State private var album: MusicItem?
    @State private var songs: [MusicItem]?
    @State private var similar: [MusicItem] = []
    @State private var alert: ItemAlert?
    @State private var showsNowPlaying = false
    @State private var placedFocus = false

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: ItemLayout.sectionSpacing) {
                    MusicHeader(details: details, artist: album?.albumArtist ?? album?.artistNames, image: coverImage) {
                        buttons
                    }
                    .id(ItemLayout.headerID)
                    songList
                    if !similar.isEmpty {
                        MusicRow(id: "similar", title: "More Like This", items: similar, focus: $focus)
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
        .defaultFocus($focus, initialFocus)
        .task(id: initialFocus) {
            // Once, when the songs are in, so a song opened from elsewhere takes focus even
            // where tvOS already put it on the first button.
            guard !placedFocus, let initialFocus else { return }
            placedFocus = true
            focus = initialFocus
        }
        .itemAlert($alert)
        .nowPlaying(isPresented: $showsNowPlaying)
        // Again after Back and in the foreground, so favourites show their new state.
        .pageTask(id: details.id) {
            await load()
        }
    }

    private var coverImage: ItemImage? {
        album?.coverImage ?? details.item.squareImage
    }

    private var initialFocus: MusicFocus? {
        if let focusedSongID, songs?.contains(where: { $0.id == focusedSongID }) == true {
            return .song(list: "songs", id: focusedSongID)
        }
        return songs == nil ? nil : .action(.play)
    }

    private var buttons: some View {
        HStack(spacing: 24) {
            MusicActionButtons(
                details: details,
                artists: album?.albumArtistLinks ?? [],
                focus: $focus,
                play: { shuffled in play(from: 0, shuffled: shuffled) },
                instantMix: {
                    player.playInstantMix(from: details.id, browse: browse) { alert = .failed($0) }
                    showsNowPlaying = true
                },
                favorite: { Task { await toggleFavorite() } },
                nowPlaying: { showsNowPlaying = true },
            )
        }
    }

    @ViewBuilder
    private var songList: some View {
        if let songs {
            VStack(alignment: .leading, spacing: 4) {
                Text(songs.count == 1 ? "1 song" : "\(songs.count) songs")
                    .font(.headline)
                    .padding(.bottom, 8)
                let showsArtist = album?.isVariousArtists ?? false
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    SongRow(song: song, number: song.trackNumber ?? index + 1, showsArtist: showsArtist) {
                        play(from: index, shuffled: false)
                    }
                    .songMenu(song) { play(from: index, shuffled: false) }
                    .focused($focus, equals: .song(list: "songs", id: song.id))
                    .accessibilityIdentifier("song.\(index)")
                }
            }
            .frame(maxWidth: ItemLayout.textWidth + 300)
            .focusSection()
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
        }
    }

    /// Like Wholphin, playing from a song queues it and the songs after it. Play or Shuffle pressed
    /// before the songs are in queues the album as the player fetches it, so the press isn't lost.
    private func play(from index: Int, shuffled: Bool) {
        guard let songs else {
            player.play(.album(details.id), shuffled: shuffled, browse: browse) { alert = .failed($0) }
            showsNowPlaying = true
            return
        }
        guard songs.indices.contains(index) else { return }
        player.play(Array(songs[index...]), shuffled: shuffled)
        showsNowPlaying = true
    }

    private func load() async {
        let session = browse.session
        let id = details.id
        async let albumResult = attempt { try await session.musicItem(id: id) }
        async let songsResult = attempt { try await session.songs(onAlbum: id) }
        let (loadedAlbum, loadedSongs) = await (albumResult, songsResult)
        if let loadedAlbum = browse.optional(loadedAlbum) {
            album = loadedAlbum
            details = loadedAlbum.details
        }
        switch loadedSongs {
        case let .success(list):
            songs = list
        case let .failure(error):
            // A failed refresh keeps the songs showing.
            if songs == nil, let message = browse.problem(with: error, doing: "load \(details.item.name)") {
                songs = []
                alert = .failed(message)
            }
        }
        if similar.isEmpty {
            let artists = album?.albumArtistLinks.map(\.id) ?? []
            similar = await browse.optional(attempt {
                try await session.similarMusic(to: id, excludingArtists: artists)
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

/// The header of an album or artist page, Wholphin's `AlbumHeader` and `ArtistHeader`: the
/// square art beside the artist, the title, quick details, genres and overview, then the
/// page's buttons.
struct MusicHeader<Buttons: View>: View {
    let details: ItemDetails
    /// Shown above the title on album pages.
    var artist: String?
    let image: ItemImage?
    @ViewBuilder let buttons: Buttons

    var body: some View {
        HStack(alignment: .top, spacing: 48) {
            MusicArtwork(image: image, width: 360)
            VStack(alignment: .leading, spacing: 8) {
                if let artist {
                    Text(artist)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .accessibilityIdentifier("detail.artist")
                }
                Text(details.item.name)
                    .font(.title.bold())
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("detail.title")
                QuickDetails(details: details)
                if !details.genres.isEmpty {
                    NameList(names: details.genres)
                }
                if let overview = details.item.overview {
                    OverviewButton(title: details.item.name, overview: overview)
                }
                buttons
                    .padding(.vertical, 20)
                    .focusSection()
            }
            .frame(maxWidth: ItemLayout.textWidth, alignment: .leading)
        }
    }
}

/// Wholphin's `MusicExpandableButtons`: Play, Shuffle, Instant Mix and favourite, then the
/// artists' pages, and Now Playing while music plays.
struct MusicActionButtons: View {
    let details: ItemDetails
    let artists: [MusicArtistLink]
    let focus: FocusState<MusicFocus?>.Binding
    let play: (_ shuffled: Bool) -> Void
    let instantMix: () -> Void
    let favorite: () -> Void
    let nowPlaying: () -> Void

    @Environment(MusicPlayer.self) private var player

    var body: some View {
        ActionButton(title: "Play", systemImage: "play.fill") {
            play(false)
        }
        .focused(focus, equals: .action(.play))
        .accessibilityIdentifier("action.play")
        ActionButton(title: "Shuffle", systemImage: "shuffle") {
            play(true)
        }
        .focused(focus, equals: .action(.shuffle))
        .accessibilityIdentifier("action.shuffle")
        ActionButton(title: "Instant Mix", systemImage: "wand.and.stars", action: instantMix)
            .focused(focus, equals: .action(.instantMix))
            .accessibilityIdentifier("action.instantMix")
        FavoriteButton(isFavorite: details.userState.isFavorite, action: favorite)
            .focused(focus, equals: .action(.favorite))
        ForEach(artists.prefix(1)) { artist in
            NavigationLink(value: artist.item) {
                Label(artist.name, systemImage: "music.mic")
            }
            .accessibilityLabel("Go to \(artist.name)")
            .focused(focus, equals: .action(.artist))
            .accessibilityIdentifier("action.artist")
        }
        if player.hasQueue {
            ActionButton(title: "Now Playing", systemImage: "waveform", action: nowPlaying)
                .focused(focus, equals: .action(.nowPlaying))
                .accessibilityIdentifier("action.nowPlaying")
        }
    }
}
