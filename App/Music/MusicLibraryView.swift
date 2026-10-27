import AnemoneJellyfin
import AnemonePlayback
import SwiftUI

/// A music library, Wholphin's `CollectionFolderMusic`: tabs for Recommended, Albums, Artists,
/// Genres and Songs, with Now Playing while music plays.
struct MusicLibraryView: View {
    let library: Library
    @Binding var path: NavigationPath

    enum Tab: String, CaseIterable, Identifiable {
        case recommended
        case albums
        case artists
        case genres
        case songs

        var id: Self {
            self
        }

        var title: String {
            switch self {
            case .recommended: "Recommended"
            case .albums: "Albums"
            case .artists: "Artists"
            case .genres: "Genres"
            case .songs: "Songs"
            }
        }
    }

    @Environment(MusicPlayer.self) private var player
    @State private var tab = Tab.recommended
    @State private var showsNowPlaying = false
    @FocusState private var focusedTab: Tab?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .nowPlaying(isPresented: $showsNowPlaying)
        .navigationDestination(for: MusicGenreLink.self) { link in
            MusicGridPage(
                title: link.name,
                list: .genre(link.id, library: link.libraryID),
                playSource: .genre(link.id, library: link.libraryID),
                path: $path,
            )
        }
        .navigationDestination(for: AlbumSongLink.self) { link in
            AlbumSongPage(link: link)
        }
    }

    /// The library's name and Wholphin's tab row; a tab shows as soon as it's focused, as tvOS
    /// tab bars do.
    private var header: some View {
        HStack(spacing: 16) {
            Text(library.name)
                .font(.title2.bold())
                .padding(.trailing, 24)
            ForEach(Tab.allCases) { item in
                Button(item.title) {
                    tab = item
                }
                .buttonStyle(MusicTabStyle(isSelected: tab == item))
                .focused($focusedTab, equals: item)
                .accessibilityIdentifier("music.tab.\(item.rawValue)")
                .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
            Spacer()
            if player.hasQueue {
                Button("Now Playing", systemImage: "waveform") {
                    showsNowPlaying = true
                }
                .accessibilityIdentifier("music.nowPlaying")
            }
        }
        .font(.callout)
        .padding(.horizontal, GridLayout.horizontalInset)
        .padding(.vertical, 20)
        .focusSection()
        .onChange(of: focusedTab) { _, focused in
            if let focused {
                tab = focused
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .recommended:
            MusicRecommendedView(library: library)
        case .albums:
            MusicGrid(
                list: .albums(library: library.id),
                playSource: .library(library.id),
                path: $path,
                showsNowPlaying: $showsNowPlaying,
            )
        case .artists:
            MusicGrid(list: .artists(library: library.id), path: $path, showsNowPlaying: $showsNowPlaying)
        case .genres:
            MusicGenresView(library: library)
        case .songs:
            MusicGrid(
                list: .songs(library: library.id),
                playSource: .library(library.id),
                path: $path,
                showsNowPlaying: $showsNowPlaying,
            )
        }
    }
}

/// A tab in a music library's tab row: underlined when it's the one showing.
private struct MusicTabStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        TabLabel(configuration: configuration, isSelected: isSelected)
    }

    private struct TabLabel: View {
        let configuration: ButtonStyleConfiguration
        let isSelected: Bool
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isFocused ? AnyShapeStyle(.black) : AnyShapeStyle(isSelected ? .primary : .secondary))
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(isFocused ? AnyShapeStyle(.white) : AnyShapeStyle(.clear), in: .capsule)
                .overlay(alignment: .bottom) {
                    if isSelected, !isFocused {
                        Capsule()
                            .fill(.tint)
                            .frame(height: 4)
                            .padding(.horizontal, 24)
                    }
                }
                .scaleEffect(isFocused ? 1.05 : 1)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}

/// A genre from the Genres tab, opening its albums.
struct MusicGenreLink: Hashable {
    let id: String
    let name: String
    let libraryID: Library.ID
}

/// A song from the Songs tab, opening its album's page focused on it, as Wholphin does.
struct AlbumSongLink: Hashable {
    let albumID: MediaItem.ID
    let songID: MediaItem.ID
}

/// The album page for a song from the Songs tab.
private struct AlbumSongPage: View {
    let link: AlbumSongLink

    @Environment(BrowseModel.self) private var browse
    @State private var album: ItemDetails?
    @State private var problem: String?

    var body: some View {
        Group {
            if let album = Binding($album) {
                AlbumPage(details: album, focusedSongID: link.songID)
            } else if let problem {
                PageMessage(message: problem)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: link) {
            guard album == nil else { return }
            let session = browse.session
            let id = link.albumID
            switch await attempt({ try await session.itemDetails(id: id) }) {
            case let .success(details):
                album = details
            case let .failure(error):
                problem = browse.problem(with: error, doing: "load the album from \(browse.server.name)")
            }
        }
    }
}
