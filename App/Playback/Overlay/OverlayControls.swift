import AnemoneJellyfin
import AnemonePlayback
import SwiftUI

/// The transport, as Wholphin's `PlaybackController` and `PlaybackControls` lay it out: the title
/// and when it ends, the seek bar, then Previous, skip back, Play/Pause, skip forward and Next,
/// with features' menus and actions on the right.
struct OverlayControls: View {
    let playback: PlaybackController
    let overlay: PlayerOverlay
    let sheets: TrickplaySheets?
    var focus: FocusState<OverlayFocus?>.Binding

    private var metadata: PlaybackMetadata {
        playback.queue.current.metadata
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(metadata.title)
                        .font(.title3.bold())
                        .lineLimit(1)
                    if let subtitle = metadata.subtitle {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    TrackSummary(playback: playback)
                }
                Spacer(minLength: 40)
                EndTime(seeker: overlay.seeker, rate: playback.engine.rate)
            }
            SeekTrack(
                seeker: overlay.seeker,
                sheets: sheets,
                isFocused: focus.wrappedValue == .seekBar,
                showsPreview: focus.wrappedValue == .seekBar && overlay.seeker.isSeeking,
                identifier: "player.seekBar",
            )
            .focusable(overlay.openMenuID == nil)
            .focused(focus, equals: .seekBar)
            ZStack {
                transport
                HStack(spacing: 20) {
                    Spacer()
                    ForEach(playback.accessories.menus) { menu in
                        menuButton(menu)
                    }
                    ForEach(playback.accessories.actions) { action in
                        PlayerActionButton(action: action)
                            .focused(focus, equals: .action(action.id))
                    }
                }
            }
            .disabled(overlay.openMenuID != nil)
        }
        .overlay(alignment: .bottomTrailing) {
            if let id = overlay.openMenuID, let menu = playback.accessories.menus.first(where: { $0.id == id }) {
                MenuPanel(menu: menu, focus: focus) {
                    overlay.closeMenu()
                    focus.wrappedValue = .menu(menu.id)
                }
                .alignmentGuide(.bottom) { $0[.bottom] + 110 }
            }
        }
    }

    private var transport: some View {
        HStack(spacing: 24) {
            transportButton(.previous, systemImage: "backward.end.fill", label: "Previous") {
                overlay.previous()
            }
            transportButton(
                .rewind,
                systemImage: skipSymbol("gobackward", overlay.seeker.skipBack),
                label: "Skip back",
            ) {
                overlay.seeker.step(.back)
                overlay.pulse()
            }
            transportButton(
                .playPause,
                systemImage: overlay.isPaused ? "play.fill" : "pause.fill",
                label: overlay.isPaused ? "Play" : "Pause",
            ) {
                overlay.togglePlayPause()
            }
            transportButton(
                .forward,
                systemImage: skipSymbol("goforward", overlay.seeker.skipForward),
                label: "Skip forward",
            ) {
                overlay.seeker.step(.forward)
                overlay.pulse()
            }
            transportButton(.next, systemImage: "forward.end.fill", label: "Next") {
                overlay.next()
            }
            .disabled(!overlay.hasNext)
        }
        .focusSection()
    }

    private func transportButton(
        _ button: TransportButton,
        systemImage: String,
        label: String,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .accessibilityLabel(label)
        }
        .buttonStyle(OverlayButtonStyle())
        .focused(focus, equals: .transport(button))
        .accessibilityIdentifier("player.\(button)")
    }

    private func menuButton(_ menu: PlayerMenu) -> some View {
        Button {
            overlay.openMenu(menu.id)
            let selected = menu.options.first(where: \.isSelected) ?? menu.options.first
            if let selected {
                focus.wrappedValue = .option(menu: menu.id, option: selected.id)
            }
        } label: {
            if let systemImage = menu.systemImage {
                Image(systemName: systemImage)
                    .accessibilityLabel(menu.title)
            } else {
                Text(menu.title)
                    .font(.callout)
            }
        }
        .buttonStyle(OverlayButtonStyle())
        .focused(focus, equals: .menu(menu.id))
        .accessibilityIdentifier("player.menu.\(menu.id)")
    }

    /// The numbered symbol for skips SF Symbols has, such as `goforward.30`, else the plain one.
    private func skipSymbol(_ base: String, _ skip: Duration) -> String {
        let seconds = Int(skip.components.seconds)
        return [5, 10, 15, 30, 45, 60, 75, 90].contains(seconds) ? "\(base).\(seconds)" : base
    }
}

/// A feature's menu, such as Audio or Subtitles, as a list over the controls. Wholphin shows these
/// as a dialog at the bottom of the screen; a list of our own, rather than SwiftUI's `Menu`, keeps
/// the controls up while it's open.
private struct MenuPanel: View {
    let menu: PlayerMenu
    var focus: FocusState<OverlayFocus?>.Binding
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(menu.title)
                .font(.headline)
                .padding(.horizontal, 20)
            ForEach(menu.options) { option in
                Button {
                    option.select()
                    close()
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "checkmark")
                            .opacity(option.isSelected ? 1 : 0)
                        Text(option.title)
                        Spacer(minLength: 0)
                    }
                    .frame(width: 520, alignment: .leading)
                }
                .focused(focus, equals: .option(menu: menu.id, option: option.id))
                .accessibilityIdentifier("player.option.\(menu.id).\(option.id)")
            }
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .focusSection()
    }
}

/// Wholphin's round transport buttons: translucent, white when focused.
struct OverlayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        OverlayButtonLabel(configuration: configuration)
    }

    private struct OverlayButtonLabel: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var isFocused
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.title3)
                .foregroundStyle(isFocused ? .black : .white)
                .frame(minWidth: 72, minHeight: 72)
                .padding(.horizontal, 8)
                .background(isFocused ? .white : .white.opacity(0.18), in: Capsule())
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(isFocused ? 1.12 : configuration.isPressed ? 0.95 : 1)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}

/// The seek bar with its times, as Wholphin's `SeekBar` and `SeekTimecodes`, and a trickplay
/// thumbnail over where the user is seeking to. Thicker while focused.
struct SeekTrack: View {
    let seeker: Seeker
    let sheets: TrickplaySheets?
    let isFocused: Bool
    let showsPreview: Bool
    /// For the bar and its time, which UI tests read.
    let identifier: String

    private var fraction: Double {
        guard let duration = seeker.duration, duration > .zero else { return 0 }
        return min(max(seeker.shownPosition / duration, 0), 1)
    }

    var body: some View {
        VStack(spacing: 12) {
            // The preview hangs above the bar without taking room, so the bar doesn't move.
            Color.clear
                .frame(height: 0)
                .overlay(alignment: .bottom) {
                    if showsPreview {
                        AlongTrack(fraction: fraction) {
                            SeekPreview(position: seeker.shownPosition, sheets: sheets)
                        }
                        .padding(.bottom, 12)
                    }
                }
            track
        }
        // One element, so focus and the time are found by the one identifier.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(showsPreview && sheets != nil ? "Seek, with a thumbnail" : "Seek")
        .accessibilityValue(seeker.shownPosition.timecode)
        .accessibilityIdentifier(identifier)
    }

    private var track: some View {
        VStack(spacing: 12) {
            GeometryReader { geometry in
                let height = geometry.size.height
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.25))
                    Capsule()
                        .fill(.white)
                        .frame(width: max(geometry.size.width * fraction, height))
                    Circle()
                        .fill(.white)
                        .frame(width: height * 2.2, height: height * 2.2)
                        .offset(x: geometry.size.width * fraction - height * 1.1)
                        .opacity(isFocused || showsPreview ? 1 : 0)
                }
            }
            .frame(height: isFocused ? 12 : 6)
            .animation(.easeOut(duration: 0.15), value: isFocused)
            HStack {
                Text(seeker.shownPosition.timecode)
                Spacer()
                Text("-" + max((seeker.duration ?? .zero) - seeker.shownPosition, .zero).timecode)
            }
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }
}

/// When playback will end at the current speed, as Wholphin's "Ends at".
private struct EndTime: View {
    let seeker: Seeker
    let rate: Float

    var body: some View {
        if let duration = seeker.duration, duration > .zero {
            let remaining = max(duration - seeker.position, .zero) / Double(max(rate, 0.1))
            Text("Ends at \(Date.now.addingTimeInterval(remaining / .seconds(1)), format: .dateTime.hour().minute())")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

/// The audio and subtitle tracks playing, as the engine lists them.
private struct TrackSummary: View {
    let playback: PlaybackController

    @State private var summary: String?

    var body: some View {
        Group {
            if let summary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .task(id: playback.queue.currentIndex) {
            let audio = await playback.engine.tracks(.audio)
            let subtitles = await playback.engine.tracks(.subtitle)
            var parts: [String] = []
            if let track = audio.first(where: \.isSelected) ?? audio.first, audio.count > 1 || !track.title.isEmpty {
                parts.append("Audio: \(track.title)")
            }
            if !subtitles.isEmpty {
                parts.append("Subtitles: \(subtitles.first(where: \.isSelected)?.title ?? "Off")")
            }
            summary = parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    }
}
