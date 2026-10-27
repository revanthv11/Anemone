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

    @Environment(MusicPlayer.self) private var player
    @Environment(BrowseModel.self) private var browse
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Preferences.musicShowsAlbumArt) private var showsAlbumArt
    @AppStorage(Preferences.musicShowsLyrics) private var showsLyrics
    @AppStorage(Preferences.musicShowsBackdrop) private var showsBackdrop
    @FocusState private var focus: Focus?
    /// The current song's lyrics, once fetched.
    @State private var lyrics: (songID: String, lyrics: Lyrics?)?
    @State private var backdrop: (songID: String, image: ItemImage?)?
    @State private var showsOptions = false

    var body: some View {
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
        .background {
            ZStack {
                Color.black
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
        .onExitCommand {
            // Like Wholphin: Back from the lyrics or the queue goes to the buttons first.
            switch focus {
            case .lyric?, .entry?:
                focus = .control(.playPause)
            default:
                dismiss()
            }
        }
        .onChange(of: player.status) { _, status in
            // Stopped here, or by a video starting.
            if status == .idle {
                dismiss()
            }
        }
        .task(id: player.current?.id) {
            await loadExtras()
        }
        .sheet(isPresented: $showsOptions) {
            NowPlayingOptions()
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
                Text(song.item.name)
                    .font(.title2.bold())
                    .lineLimit(2)
                    .accessibilityIdentifier("nowPlaying.title")
                if let album = song.albumName {
                    Text(album)
                        .font(.title3)
                        .lineLimit(1)
                }
                if let artists = song.artistNames {
                    Text(artists)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if player.status == .failed {
                    Text(player.failure.map(browse.playbackProblem(with:)) ?? "Couldn't play this song.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
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
            control(.playPause, player.isPlaying ? "pause.fill" : "play.fill", player.isPlaying ? "Pause" : "Play") {
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
            control(.shuffle, "shuffle", "Shuffle", isOn: player.queue.isShuffled) {
                player.toggleShuffle()
            }
            control(.repeatMode, repeatSymbol, "Repeat", isOn: player.queue.repeatMode != .off) {
                player.cycleRepeatMode()
            }
            .accessibilityValue(repeatDescription)
            control(.options, "ellipsis", "Options") {
                showsOptions = true
            }
        }
        .focusSection()
    }

    private var repeatSymbol: String {
        player.queue.repeatMode == .one ? "repeat.1" : "repeat"
    }

    private var repeatDescription: String {
        switch player.queue.repeatMode {
        case .off: "Off"
        case .all: "All"
        case .one: "One"
        }
    }

    private func control(
        _ control: Control,
        _ systemImage: String,
        _ title: String,
        isOn: Bool? = nil,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .foregroundStyle(isOn == true ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .frame(width: 40, height: 40)
        }
        .buttonBorderShape(.circle)
        .focused($focus, equals: .control(control))
        .accessibilityLabel(title)
        .accessibilityValue(isOn.map { $0 ? "On" : "Off" } ?? "")
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
