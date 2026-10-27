import AnemoneJellyfin
import AnemonePlayback
import AnemoneUI
import SwiftUI

/// What has focus on a music page.
enum MusicFocus: Hashable {
    case action(MusicAction)
    case overview
    /// A song in one of the page's lists.
    case song(list: String, id: String)
    case card(row: String, item: String)

    /// Whether this is part of a page's header, which should scroll fully into view.
    var isInHeader: Bool {
        switch self {
        case .action, .overview: true
        case .song, .card: false
        }
    }
}

/// The buttons under a music page's header, Wholphin's `MusicExpandableButtons`.
enum MusicAction: Hashable {
    case play
    case shuffle
    case instantMix
    case favorite
    case artist
    case nowPlaying
}

/// A square card for an album, artist or song, with Wholphin's subtitle and favourite mark.
struct MusicCard: View {
    let item: MusicItem
    var width = CardShape.square.cardWidth

    @Environment(BrowseModel.self) private var browse
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        MediaCard(
            title: item.item.name,
            subtitle: item.subtitle,
            imageURL: browse.imageURL(item.coverImage, width: width * displayScale),
            shape: .square,
            width: width,
            badges: CardBadges(isFavorite: item.details.userState.isFavorite),
        )
    }
}

/// A row of albums or artists that open their pages, like the rows on Wholphin's music pages.
struct MusicRow: View {
    let id: String
    let title: String
    let items: [MusicItem]
    let focus: FocusState<MusicFocus?>.Binding

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(theme.onBackground)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: ItemLayout.cardSpacing) {
                    ForEach(items) { item in
                        NavigationLink(value: item.item) {
                            MusicCard(item: item)
                        }
                        .buttonStyle(.borderless)
                        .focused(focus, equals: .card(row: id, item: item.id))
                        .accessibilityIdentifier("card.\(id).\(item.id)")
                    }
                }
                .padding(.vertical, ItemLayout.focusPadding)
            }
            .scrollClipDisabled()
        }
        .focusSection()
    }
}

/// One song in a list, as Wholphin's `SongListItem` shows it: a mark when it's playing or
/// queued, its number, title, artists when they differ from the album's, and length.
struct SongRow: View {
    let song: MusicItem
    let number: Int?
    var showsArtist = false
    let action: () -> Void

    @Environment(MusicPlayer.self) private var player
    @Environment(\.theme) private var theme

    var body: some View {
        // No label of its own: VoiceOver reads the row's parts in order, whether the song is
        // playing or queued, its name, its artists where shown, the favourite mark and length.
        Button(action: action) {
            HStack(spacing: 24) {
                marker
                    .frame(width: 32)
                Text(number.map(String.init) ?? "")
                    .monospacedDigit()
                    .foregroundStyle(theme.secondaryText)
                    .frame(width: 60, alignment: .trailing)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(song.item.name)
                        .foregroundStyle(theme.onBackground)
                        .lineLimit(1)
                    if showsArtist, let artists = song.artistNames {
                        Text(artists)
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 24)
                if song.details.userState.isFavorite {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(theme.favorite)
                        .accessibilityLabel("Favorite")
                }
                Text(song.item.runtime?.clockText ?? "")
                    .monospacedDigit()
                    .foregroundStyle(theme.secondaryText)
                    .accessibilityLabel(song.item.runtime?.spokenTime ?? "")
            }
            .font(.callout)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .buttonStyle(RowButtonStyle())
    }

    @ViewBuilder
    private var marker: some View {
        if player.current?.id == song.id {
            Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                .foregroundStyle(theme.highlight)
                .accessibilityLabel("Playing")
        } else if player.queue.contains(song.id) {
            Circle()
                .frame(width: 10, height: 10)
                .foregroundStyle(theme.secondaryText)
                .accessibilityLabel("Queued")
        }
    }
}

/// Shows focus as a soft bar behind a list row, like Wholphin's list items, in the theme's
/// platter.
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RowBody(configuration: configuration)
    }

    private struct RowBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var isFocused
        @Environment(\.theme) private var theme

        var body: some View {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isFocused ? theme.platter.color : .clear, in: .rect(cornerRadius: 12))
                .scaleEffect(configuration.isPressed ? 0.98 : isFocused ? 1.02 : 1)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}

/// Wholphin's per-song menu (`MusicContextActions`), on a long press: play now, next or last,
/// and go to the album or artist.
struct SongMenu: ViewModifier {
    let song: MusicItem
    let play: () -> Void

    @Environment(MusicPlayer.self) private var player

    func body(content: Content) -> some View {
        content.contextMenu {
            Button("Play", systemImage: "play.fill", action: play)
            Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                player.playNext([song])
            }
            Button("Add to Queue", systemImage: "text.append") {
                player.addToQueue([song])
            }
            if let albumID = song.albumID {
                NavigationLink(value: MediaItem(id: albumID, name: song.albumName ?? "", kind: .musicAlbum)) {
                    Label("Go to Album", systemImage: "square.stack")
                }
            }
            ForEach(song.artistLinks) { artist in
                NavigationLink(value: artist.item) {
                    Label("Go to \(artist.name)", systemImage: "music.mic")
                }
            }
        }
    }
}

extension View {
    func songMenu(_ song: MusicItem, play: @escaping () -> Void) -> some View {
        modifier(SongMenu(song: song, play: play))
    }
}

/// A music page's square art, Wholphin's album and artist header image.
struct MusicArtwork: View {
    let image: ItemImage?
    let width: CGFloat

    @Environment(BrowseModel.self) private var browse
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ShapedArtwork(url: browse.imageURL(image, width: width * displayScale), shape: .square, width: width)
            .accessibilityHidden(true)
    }
}
