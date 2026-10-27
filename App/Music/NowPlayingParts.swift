import AnemoneCore
import AnemoneJellyfin
import AnemonePlayback
import AnemoneUI
import SwiftUI

/// The song's lyrics beside the cover, Wholphin's `LyricsContent`: the line being sung stands
/// out and stays in the middle. Focusing the lyrics stops them moving, and selecting a line
/// jumps to it.
struct LyricsView: View {
    let lyrics: Lyrics
    let position: Duration
    let focus: FocusState<NowPlayingPage.Focus?>.Binding
    let seek: (Duration) -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        let current = lyrics.lineIndex(at: position)
        ScrollViewReader { scroller in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { index, line in
                        Button {
                            if let start = line.start {
                                seek(start - lyrics.offset)
                            }
                        } label: {
                            Text(line.text.isEmpty ? " " : line.text)
                                .font(.title3.weight(index == current ? .bold : .regular))
                                .foregroundStyle(
                                    index == current || current == nil ? theme.onBackground : theme.secondaryText,
                                )
                                .multilineTextAlignment(.leading)
                        }
                        .buttonStyle(HighlightButtonStyle())
                        .focused(focus, equals: .lyric(index))
                        .id(index)
                        // A gap between verses reads as one, rather than as nothing.
                        .accessibilityLabel(line.text.isEmpty ? Text("Instrumental") : Text(verbatim: line.text))
                        .accessibilityHint(line.start == nil ? Text(verbatim: "") : Text("Plays from this line"))
                        .accessibilityIdentifier("nowPlaying.lyric.\(index)")
                        // The line being sung.
                        .accessibilityAddTraits(index == current ? .isSelected : [])
                    }
                }
                .padding(.vertical, 160)
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .onChange(of: current) { _, line in
                guard let line, !hasFocus else { return }
                withAnimation(.easeInOut(duration: 0.5)) {
                    scroller.scrollTo(line, anchor: .center)
                }
            }
            .onAppear {
                if let current {
                    scroller.scrollTo(current, anchor: .center)
                }
            }
        }
        .focusSection()
        .accessibilityIdentifier("nowPlaying.lyrics")
    }

    private var hasFocus: Bool {
        if case .lyric? = focus.wrappedValue {
            true
        } else {
            false
        }
    }
}

/// The song's progress, as Wholphin's seek bar shows it on Now Playing: not focusable, with
/// the time played and the length.
struct NowPlayingProgress: View {
    let position: Duration
    let duration: Duration?

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                Capsule()
                    .fill(theme.seekTrack)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(theme.seekPlayed)
                            .frame(width: geometry.size.width * fraction)
                    }
            }
            .frame(height: 8)
            HStack {
                Text(position.clockText)
                Spacer()
                Text(duration?.clockText ?? "")
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(theme.secondaryText)
        }
        // One element, read as how far the song has got of how long it is.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Position")
        .accessibilityValue(spokenProgress)
        .accessibilityIdentifier("nowPlaying.position")
    }

    /// "1 minute, 5 seconds of 3 minutes, 20 seconds".
    private var spokenProgress: Text {
        guard let duration, duration > .zero else { return Text(position.spokenPosition) }
        return Text("\(position.spokenPosition) of \(duration.spokenPosition)")
    }

    private var fraction: CGFloat {
        guard let duration, duration > .zero else { return 0 }
        return CGFloat(min(max(position / duration, 0), 1))
    }
}

/// The queue in the order it plays, Wholphin's queue list. Selecting a song plays it; a long
/// press moves it, plays it next or takes it out.
struct UpNextRow: View {
    let focus: FocusState<NowPlayingPage.Focus?>.Binding

    @Environment(MusicPlayer.self) private var player
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Queue")
                .font(.headline)
                .foregroundStyle(theme.onBackground)
                .accessibilityAddTraits(.isHeader)
            ScrollViewReader { scroller in
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 32) {
                        ForEach(Array(player.queue.entries.enumerated()), id: \.element.id) { index, entry in
                            card(entry, at: index)
                        }
                    }
                    .padding(.vertical, 20)
                }
                .scrollClipDisabled()
                .onAppear {
                    if let current = player.queue.current?.id {
                        scroller.scrollTo(current, anchor: .leading)
                    }
                }
            }
        }
        .focusSection()
        .defaultFocus(focus, player.queue.current.map { .entry($0.id) }, priority: .userInitiated)
    }

    private func card(_ entry: MusicQueue.Entry, at index: Int) -> some View {
        let isCurrent = index == player.queue.currentIndex
        let last = player.queue.entries.count - 1
        return Button {
            player.playEntry(at: index)
        } label: {
            MusicCard(item: entry.song, width: 150)
                .overlay(alignment: .topTrailing) {
                    if isCurrent {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.caption2.bold())
                            .foregroundStyle(theme.onCardBadge)
                            .padding(10)
                            .background(theme.cardBadge, in: .circle)
                            .padding(8)
                            .accessibilityHidden(true)
                    }
                }
        }
        .buttonStyle(.borderless)
        .contextMenu {
            Button("Play", systemImage: "play.fill") {
                player.playEntry(at: index)
            }
            if let current = player.queue.currentIndex, index != current, index != current + 1 {
                // Wholphin moves the song to the second place; here it goes after the current one.
                Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                    player.moveEntry(from: index, to: index > current ? current + 1 : current)
                }
            }
            if index > 0 {
                Button("Move Earlier", systemImage: "arrow.left") {
                    player.moveEntry(from: index, to: index - 1)
                }
            }
            if index < last {
                Button("Move Later", systemImage: "arrow.right") {
                    player.moveEntry(from: index, to: index + 1)
                }
            }
            Button("Remove from Queue", systemImage: "minus.circle", role: .destructive) {
                player.removeEntry(at: index)
            }
        }
        .id(entry.id)
        .focused(focus, equals: .entry(entry.id))
        // The card reads the song, its album and artists; the one playing says so.
        .accessibilityValue(isCurrent ? Text("Playing") : Text(verbatim: ""))
        .accessibilityIdentifier("nowPlaying.queue.\(index)")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

/// Wholphin's Now Playing view options (`MusicViewOptionsDialog`), and its experimental AC3
/// setting, which only music uses.
struct NowPlayingOptions: View {
    @AppStorage(Preferences.musicShowsAlbumArt) private var showsAlbumArt
    @AppStorage(Preferences.musicShowsLyrics) private var showsLyrics
    @AppStorage(Preferences.musicShowsBackdrop) private var showsBackdrop
    @AppStorage(Preferences.preferAC3Surround) private var prefersAC3

    var body: some View {
        Form {
            Section("Now Playing") {
                Toggle("Show album cover", isOn: $showsAlbumArt)
                Toggle("Show lyrics", isOn: $showsLyrics)
                Toggle("Show backdrop", isOn: $showsBackdrop)
            }
            Section {
                Toggle("Use AC3 for surround sound audio", isOn: $prefersAC3)
            } footer: {
                Text("Transcodes non-stereo audio to AC3/Dolby Digital. Takes effect from the next song.")
            }
        }
        .frame(maxWidth: 1000)
    }
}
