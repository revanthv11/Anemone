import AnemoneCore
import AnemoneJellyfin
import AnemonePlayback
import AnemoneUI
import SwiftUI

/// Wholphin's Now Playing page (`NowPlayingPage`): the cover and song beside its lyrics, which
/// follow the song, then the progress, the transport buttons, and the queue. Back leaves the
/// page and the music plays on; Stop ends it.
///
/// Wholphin's queue is a list that grows over the page when focused; here it's an Up Next row
/// along the bottom, as on Apple TV, so the lyrics keep their own scrolling.
///
/// It shows over everything when music starts from a page, and in the sidebar's Now Playing
/// entry (`NowPlayingTab`), as Wholphin's drawer opens it. Like Wholphin, which keeps the screen
/// on only for video and slideshows, the in-app screensaver can come over it; the music plays on
/// meanwhile, and the first press only closes the screensaver.
struct NowPlayingPage: View {
    enum Focus: Hashable {
        case control(Control)
        case lyric(Int)
        case entry(MusicQueue.Entry.ID)
    }

    enum Control: Hashable {
        case stop
        case previous
        case rewind
        case playPause
        case forward
        case next
        case shuffle
        case repeatMode
        case options
    }

    /// Set when the sidebar shows the page: called once the music stops, to move to another
    /// entry. Back from the buttons then opens the sidebar, as on its other pages.
    var stopped: (() -> Void)?

    @Environment(MusicPlayer.self) private var player
    @Environment(BrowseModel.self) private var browse
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @AppStorage(Preferences.musicShowsAlbumArt) private var showsAlbumArt
    @AppStorage(Preferences.musicShowsLyrics) private var showsLyrics
    @AppStorage(Preferences.musicShowsBackdrop) private var showsBackdrop
    @FocusState private var focus: Focus?
    /// The current song's lyrics, once fetched.
    @State private var lyrics: (songID: String, lyrics: Lyrics?)?
    @State private var backdrop: (songID: String, image: ItemImage?)?
    @State private var showsOptions = false

    var body: some View {
        Group {
            if stopped == nil {
                page
            } else {
                // Back first scrolls the page's scroll view back to its top, and that would be
                // the lyrics, which stay on the line being sung, so Back never reached the
                // sidebar. tvOS looks at this one instead, which the page fills exactly, so it
                // never scrolls.
                ScrollView(.vertical) {
                    page
                        .containerRelativeFrame(.vertical, alignment: .top)
                }
            }
        }
        .background {
            ZStack {
                // It covers the app's root, so it brings the theme's background with it.
                theme.background.color
                if showsBackdrop, let image = backdrop?.image {
                    BackdropImage(url: browse.imageURL(image, width: ItemLayout.backdropPixelWidth))
                }
            }
            .ignoresSafeArea()
        }
        .defaultFocus($focus, .control(.playPause))
        .onPlayPauseCommand {
            player.togglePlayPause()
        }
        .onExitCommand(perform: exitAction)
        .onChange(of: player.status) { _, status in
            // Stopped here, or by a video starting.
            if status == .idle {
                if let stopped {
                    stopped()
                } else {
                    dismiss()
                }
            }
        }
        .task(id: player.current?.id) {
            await loadExtras()
        }
        .sheet(isPresented: $showsOptions) {
            NowPlayingOptions()
        }
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 80) {
                songDetails
                if showsLyrics, let shown = currentLyrics {
                    LyricsView(lyrics: shown, position: player.position, focus: $focus) { start in
                        player.seek(to: start)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            // Leaves room for the queue below on a 1080p screen.
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 430)
            NowPlayingProgress(position: player.position, duration: player.duration ?? player.current?.item.runtime)
            controls
            UpNextRow(focus: $focus)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 80)
        .padding(.top, 40)
    }

    /// Like Wholphin: Back from the lyrics or the queue goes to the buttons first. From the
    /// buttons it leaves the page, or in the sidebar is left to the sidebar.
    private var exitAction: (() -> Void)? {
        switch focus {
        case .lyric?, .entry?:
            { focus = .control(.playPause) }
        default:
            stopped == nil ? { dismiss() } : nil
        }
    }

    private var currentLyrics: Lyrics? {
        guard let lyrics, lyrics.songID == player.current?.id else { return nil }
        return lyrics.lyrics
    }

    @ViewBuilder
    private var songDetails: some View {
        if let song = player.current {
            VStack(alignment: .leading, spacing: 8) {
                if showsAlbumArt {
                    MusicArtwork(image: song.coverImage, width: 200)
                        .padding(.bottom, 12)
                }
                // One element, so VoiceOver reads the song, its album and its artists together,
                // as the page's heading.
                VStack(alignment: .leading, spacing: 8) {
                    Text(song.item.name)
                        .font(.title2.bold())
                        .foregroundStyle(theme.onBackground)
                        .lineLimit(2)
                    if let album = song.albumName {
                        Text(album)
                            .font(.title3)
                            .foregroundStyle(theme.onBackground)
                            .lineLimit(1)
                    }
                    if let artists = song.artistNames {
                        Text(artists)
                            .font(.title3)
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("nowPlaying.title")
                if player.status == .failed {
                    Text(player.failure.map(browse.playbackProblem(with:)) ?? "Couldn't play this song.")
                        .font(.callout)
                        .foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: 600, alignment: .leading)
                        .accessibilityIdentifier("nowPlaying.problem")
                }
            }
            .frame(width: 560, alignment: .leading)
        } else if player.status == .loading {
            ProgressView()
                .frame(width: 560)
        } else {
            Text("Nothing is playing.")
                .foregroundStyle(theme.secondaryText)
        }
    }

    private var controls: some View {
        HStack(spacing: 32) {
            control(.stop, "stop.fill", "Stop") {
                player.stop()
            }
            Spacer()
            control(.previous, "backward.end.fill", "Previous") {
                player.previous()
            }
            control(.rewind, "gobackward.10", "Back 10 seconds") {
                player.skip(by: .seconds(-10))
            }
            control(
                .playPause,
                player.isPlaying ? "pause.fill" : "play.fill",
                player.isPlaying ? "Pause" : "Play",
                value: player.isPlaying ? Text("Playing") : Text("Paused"),
            ) {
                player.togglePlayPause()
            }
            control(.forward, "goforward.30", "Forward 30 seconds") {
                player.skip(by: .seconds(30))
            }
            control(.next, "forward.end.fill", "Next") {
                player.next()
            }
            .disabled(player.queue.nextIndex(automatic: false) == nil)
            Spacer()
            control(
                .shuffle,
                "shuffle",
                "Shuffle",
                value: player.queue.isShuffled ? Text("On") : Text("Off"),
                isOn: player.queue.isShuffled,
            ) {
                player.toggleShuffle()
            }
            control(
                .repeatMode,
                repeatSymbol,
                "Repeat",
                value: repeatDescription,
                isOn: player.queue.repeatMode != .off,
            ) {
                player.cycleRepeatMode()
            }
            control(.options, "ellipsis", "Options") {
                showsOptions = true
            }
        }
        .focusSection()
    }

    private var repeatSymbol: String {
        player.queue.repeatMode == .one ? "repeat.1" : "repeat"
    }

    private var repeatDescription: Text {
        switch player.queue.repeatMode {
        case .off: Text("Off")
        case .all: Text("All")
        case .one: Text("One")
        }
    }

    /// A round button. VoiceOver reads `title`, then `value`: whether the song is playing, or
    /// how a toggle is set.
    private func control(
        _ control: Control,
        _ systemImage: String,
        _ title: LocalizedStringKey,
        value: Text? = nil,
        isOn: Bool = false,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            ToggleSymbol(systemImage: systemImage, isOn: isOn)
        }
        .buttonBorderShape(.circle)
        .focused($focus, equals: .control(control))
        .accessibilityLabel(title)
        .accessibilityValue(value ?? Text(verbatim: ""))
        .accessibilityIdentifier("nowPlaying.\(control)")
    }

    /// The song's lyrics, as Wholphin fetches them when the song says it has some, and the
    /// backdrop of the first of its artists that has one, as Wholphin's backdrop shows.
    private func loadExtras() async {
        guard let song = player.current else { return }
        let session = browse.session
        if lyrics?.songID != song.id {
            let fetched = song.hasLyrics ? await browse
                .optional(attempt { try await session.lyrics(for: song.id) }) : nil
            guard !Task.isCancelled else { return }
            lyrics = (song.id, fetched ?? nil)
        }
        if backdrop?.songID != song.id {
            var image: ItemImage?
            for artist in song.artistLinks.prefix(3) where image == nil {
                image = await browse.optional(attempt { try await session.item(id: artist.id) })?.backdropImage
            }
            guard !Task.isCancelled else { return }
            backdrop = (song.id, image)
        }
    }
}

/// A Now Playing button's symbol, in the theme's highlight while its toggle is on, as Wholphin
/// brightens an active shuffle or repeat. The system's light focused button keeps its own dark
/// label, which a light highlight would vanish on; VoiceOver reads the setting either way.
private struct ToggleSymbol: View {
    let systemImage: String
    let isOn: Bool

    @Environment(\.isFocused) private var isFocused
    @Environment(\.theme) private var theme

    var body: some View {
        Image(systemName: systemImage)
            .foregroundStyle(isOn && !isFocused ? AnyShapeStyle(theme.highlight) : AnyShapeStyle(.primary))
            .frame(width: 40, height: 40)
    }
}
