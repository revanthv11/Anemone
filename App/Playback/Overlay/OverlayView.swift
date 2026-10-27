import AnemoneCore
import AnemoneJellyfin
import AnemonePlayback
import AnemoneUI
import SwiftUI

/// What can hold focus on the overlay.
enum OverlayFocus: Hashable {
    case seekBar
    case transport(TransportButton)
    case menu(PlayerMenu.ID)
    case option(menu: PlayerMenu.ID, option: PlayerMenu.Option.ID)
    case action(PlayerAction.ID)
    /// The controls' button that skips the rest of the segment playing.
    case skipSegment
    /// The row titles under the transport and the chapter row, which show their row when focus
    /// reaches them, as in Wholphin.
    case chaptersTitle
    case queueTitle
    /// Invisible lines above the chapter and queue rows, which go back up a row when focus
    /// reaches them, as Wholphin's `HiddenFocusBox` does.
    case backToControls
    case backToChapters
    /// A chapter by its `Chapter.id`, from the server's index, not its place in the row.
    case chapter(Chapter.ID)
    case queueEntry(Int)
}

enum TransportButton: Hashable {
    case previous
    case rewind
    case playPause
    case forward
    case next
}

/// Wholphin's `PlaybackOverlay` in SwiftUI: the controls, the chapter and queue rows, the compact
/// seek bar while seeking with the controls hidden, a pause indicator, features' actions and
/// menus, and the debug panel. `PlayerOverlay` decides what shows; this draws it and tells it
/// where focus is.
struct OverlayView: View {
    let playback: PlaybackController
    let overlay: PlayerOverlay
    let session: JellyfinSession

    @AppStorage(Preferences.showDebugInfo) private var showsDebugInfo
    @FocusState private var focus: OverlayFocus?
    @State private var sheets: TrickplaySheets?

    private var details: PlaybackDetails? {
        playback.feature(PlaybackDetails.self)
    }

    private var chapters: [Chapter] {
        details?.previews?.chapters ?? []
    }

    /// The entries after the one playing, with their places in the queue, without intros.
    private var upcoming: [(index: Int, entry: PlaybackQueue.Entry)] {
        playback.queue.upcoming
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if overlay.controlsVisible {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.5), .black.opacity(0.85)],
                    startPoint: .center,
                    endPoint: .bottom,
                )
                .ignoresSafeArea()
                .transition(.opacity)
            }
            DrawnSubtitlesView(playback: playback, overlay: overlay)
            PauseIndicator(isPaused: overlay.isPaused && !overlay.controlsVisible && !overlay.showsSeekBar)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if overlay.showsSeekBar, !overlay.controlsVisible {
                SeekTrack(
                    seeker: overlay.seeker,
                    sheets: sheets,
                    isFocused: false,
                    showsPreview: true,
                    identifier: "player.compactSeekBar",
                )
                .padding(.horizontal, 80)
                .padding(.bottom, 60)
                .background(alignment: .bottom) {
                    // Keeps the times readable over bright video.
                    LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 240)
                        .ignoresSafeArea()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if overlay.controlsVisible {
                page
                    .padding(.horizontal, 80)
                    .padding(.bottom, 60)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if !playback.accessories.actions.isEmpty {
                actions
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 80)
                    .padding(.bottom, 80)
            }
        }
        .overlay(alignment: .topLeading) {
            if showsDebugInfo, overlay.controlsVisible {
                OverlayDebugPanel(playback: playback, overlay: overlay, details: details)
                    .padding(60)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: overlay.controlsVisible)
        .animation(.easeInOut(duration: 0.25), value: overlay.showsSeekBar)
        .animation(.easeInOut(duration: 0.25), value: overlay.page)
        .task(id: overlay.showsPosition) {
            // Wholphin's seek bar reads the player's position every 250 ms while it shows. With
            // nothing showing it, reading it would only redraw the overlay for nothing.
            guard overlay.showsPosition else { return }
            while !Task.isCancelled {
                overlay.seeker.refresh()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        .onChange(of: focus) { _, focus in
            followFocus(focus)
        }
        .onChange(of: overlay.controlsVisible) { _, visible in
            focus = visible ? .transport(.playPause) : playback.accessories.actions.first.map { .action($0.id) }
        }
        .onChange(of: playback.accessories.actions.map(\.id)) { _, ids in
            // A new action over the video takes focus, as the system player's do.
            if !overlay.controlsVisible, let first = ids.first {
                focus = .action(first)
            }
        }
        .onChange(of: playback.accessories.card?.id) { _, card in
            // Out of the card's way; it takes focus itself.
            if card != nil {
                overlay.hideControls()
            }
        }
        .onChange(of: playback.queue.currentIndex) {
            overlay.seeker.cancel()
        }
        .onChange(of: details?.previews?.trickplay, initial: true) { _, trickplay in
            sheets = trickplay.map { TrickplaySheets(trickplay: $0, session: session) }
        }
    }

    @ViewBuilder
    private var page: some View {
        switch overlay.page {
        case .controls:
            VStack(alignment: .leading, spacing: 24) {
                OverlayControls(
                    playback: playback,
                    overlay: overlay,
                    sheets: sheets,
                    focus: $focus,
                )
                if !chapters.isEmpty {
                    rowTitle("Chapters", focus: .chaptersTitle, identifier: "player.chapters")
                } else if !upcoming.isEmpty {
                    rowTitle("Queue", focus: .queueTitle, identifier: "player.queue")
                }
            }
            // Wholphin's controls open on Play/Pause.
            .defaultFocus($focus, .transport(.playPause))
        case .chapters:
            VStack(alignment: .leading, spacing: 24) {
                focusLine(.backToControls)
                ChapterRow(
                    chapters: chapters,
                    playing: overlay.seeker.position,
                    session: session,
                    focus: $focus,
                ) { chapter in
                    overlay.jump(to: chapter)
                }
                if !upcoming.isEmpty {
                    rowTitle("Queue", focus: .queueTitle, identifier: "player.queue")
                }
            }
        case .queue:
            VStack(alignment: .leading, spacing: 24) {
                focusLine(chapters.isEmpty ? .backToControls : .backToChapters)
                QueueRow(entries: upcoming, focus: $focus) { index in
                    overlay.play(entryAt: index)
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 24) {
            ForEach(playback.accessories.actions) { action in
                PlayerActionButton(action: action)
                    .focused($focus, equals: .action(action.id))
            }
        }
        .focusSection()
    }

    /// A row's title, which shows the row when focus reaches it. Its section spans the width, so
    /// moving down from anywhere above finds it.
    private func rowTitle(_ title: String, focus target: OverlayFocus, identifier: String) -> some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(focus == target ? .primary : .secondary)
                .focusable()
                .focused($focus, equals: target)
                .accessibilityIdentifier(identifier)
            Spacer(minLength: 0)
        }
        .focusSection()
    }

    /// A line too faint to see that can still hold focus, for going back up a row.
    private func focusLine(_ target: OverlayFocus) -> some View {
        Color.white.opacity(0.001)
            .frame(maxWidth: .infinity)
            .frame(height: 2)
            .focusable()
            .focused($focus, equals: target)
    }

    /// Tells the overlay where focus is, and moves between its pages when focus reaches a row
    /// title or the line above a row.
    private func followFocus(_ focus: OverlayFocus?) {
        overlay.focus = switch focus {
        case nil: overlay.controlsVisible ? .control : .video
        case .seekBar: .seekBar
        case .action: .action
        default: .control
        }
        overlay.pulse()
        switch focus {
        case .chaptersTitle:
            overlay.show(.chapters)
            moveFocus(to: ChapterRow.playingFocus(chapters, at: overlay.seeker.position))
        case .queueTitle:
            overlay.show(.queue)
            moveFocus(to: upcoming.first.map { .queueEntry($0.index) })
        case .backToControls:
            overlay.show(.controls)
            moveFocus(to: .transport(.playPause))
        case .backToChapters:
            overlay.show(.chapters)
            moveFocus(to: ChapterRow.playingFocus(chapters, at: overlay.seeker.position))
        default:
            break
        }
    }

    /// Once the new page is on screen.
    private func moveFocus(to target: OverlayFocus?) {
        Task {
            focus = target
        }
    }
}

/// A feature's action, such as Skip Intro, in the style of the system player's.
struct PlayerActionButton: View {
    let action: PlayerAction

    var body: some View {
        Button(action: action.perform) {
            if let systemImage = action.systemImage {
                Label(action.title, systemImage: systemImage)
            } else {
                Text(action.title)
            }
        }
        .accessibilityIdentifier("player.action.\(action.id)")
    }
}

/// A pause symbol for a moment when playback pauses with the controls hidden, as Wholphin's
/// `PauseIndicator`.
private struct PauseIndicator: View {
    let isPaused: Bool

    @State private var isShowing = false

    var body: some View {
        Image(systemName: "pause.fill")
            .font(.system(size: 72))
            .foregroundStyle(.white)
            .padding(40)
            .background(.black.opacity(0.4), in: Circle())
            .scaleEffect(isShowing ? 1 : 0.6)
            .opacity(isShowing ? 1 : 0)
            .animation(.easeOut(duration: 0.3), value: isShowing)
            .task(id: isPaused) {
                guard isPaused else {
                    isShowing = false
                    return
                }
                isShowing = true
                try? await Task.sleep(for: .milliseconds(900))
                isShowing = false
            }
            .accessibilityHidden(true)
    }
}
