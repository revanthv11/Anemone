import AnemoneJellyfin
import AnemonePlayback
import AnemoneUI
import SwiftUI

/// The transport, as Wholphin's `PlaybackController` and `PlaybackControls` lay it out: the title
/// and when it ends, the seek bar, then Previous, skip back, Play/Pause, skip forward and Next,
/// with features' menus and actions on the right.
struct OverlayControls: View {
    let playback: PlaybackController
    let overlay: PlayerOverlay
    let sheets: TrickplaySheets?
    var focus: FocusState<OverlayFocus?>.Binding

    @Environment(\.theme) private var theme

    private var metadata: PlaybackMetadata {
        playback.queue.current.metadata
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(metadata.title)
                        .font(.title3.bold())
                        .foregroundStyle(theme.onBackground)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle = metadata.subtitle {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(theme.secondaryText)
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
            // VoiceOver's swipe up and down steps through the video, as left and right do.
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: overlay.seeker.step(.forward)
                case .decrement: overlay.seeker.step(.back)
                @unknown default: return
                }
                overlay.pulse()
            }
            ZStack {
                transport
                HStack(spacing: 20) {
                    Spacer()
                    if let segment = overlay.skippableSegment {
                        skipSegmentButton(segment)
                    }
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
                }
                .alignmentGuide(.bottom) { $0[.bottom] + 110 }
            }
        }
        .onChange(of: overlay.openMenuID) { closed, open in
            // Back on the menu's button, whether a choice closed the list or Menu did.
            if open == nil, let closed, overlay.controlsVisible {
                focus.wrappedValue = .menu(closed)
            }
        }
        .onChange(of: overlay.skipButtonLeftFocus) { _, left in
            // Its segment ended while the skip button had focus: Play/Pause, as after pressing it.
            if left {
                focus.wrappedValue = .transport(.playPause)
            }
        }
    }

    private var transport: some View {
        HStack(spacing: 24) {
            transportButton(.previous, systemImage: "backward.end.fill", label: Text("Previous")) {
                overlay.previous()
            }
            transportButton(
                .rewind,
                systemImage: skipSymbol("gobackward", overlay.seeker.skipBack),
                label: Text("Skip back \(overlay.seeker.skipBack.spokenTime)"),
            ) {
                overlay.seeker.step(.back)
                overlay.pulse()
            }
            transportButton(
                .playPause,
                systemImage: overlay.isPaused ? "play.fill" : "pause.fill",
                label: overlay.isPaused ? Text("Play") : Text("Pause"),
                value: overlay.isPaused ? Text("Paused") : Text("Playing"),
            ) {
                overlay.togglePlayPause()
            }
            transportButton(
                .forward,
                systemImage: skipSymbol("goforward", overlay.seeker.skipForward),
                label: Text("Skip forward \(overlay.seeker.skipForward.spokenTime)"),
            ) {
                overlay.seeker.step(.forward)
                overlay.pulse()
            }
            transportButton(.next, systemImage: "forward.end.fill", label: Text("Next")) {
                overlay.next()
            }
            .disabled(!overlay.hasNext)
        }
        .focusSection()
    }

    /// A round transport button. VoiceOver reads `label`, what it does, then `value`, such as
    /// whether the video is playing.
    private func transportButton(
        _ button: TransportButton,
        systemImage: String,
        label: Text,
        value: Text? = nil,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(OverlayButtonStyle())
        .focused(focus, equals: .transport(button))
        .accessibilityLabel(label)
        .accessibilityValue(value ?? Text(verbatim: ""))
        .accessibilityIdentifier("player.\(button)")
    }

    /// Wholphin's button beside the menus that skips the rest of the intro, credits or other
    /// segment playing, after its own button over the video has gone.
    private func skipSegmentButton(_ segment: MediaSegment) -> some View {
        Button {
            overlay.skipRest(of: segment)
            // Before the button goes, once playback is past the segment.
            focus.wrappedValue = .transport(.playPause)
        } label: {
            Label(segment.kind.skipTitle, systemImage: "forward.end.fill")
        }
        .focused(focus, equals: .skipSegment)
        .accessibilityIdentifier("player.skipSegment")
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
            } else {
                Text(menu.title)
                    .font(.callout)
            }
        }
        .buttonStyle(OverlayButtonStyle())
        .focused(focus, equals: .menu(menu.id))
        // The menu, then what's chosen in it, such as "Subtitles, English".
        .accessibilityLabel(menu.title)
        .accessibilityValue(menu.options.first(where: \.isSelected)?.title ?? "")
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
                .accessibilityAddTraits(.isHeader)
            ForEach(menu.options) { option in
                Button {
                    option.select()
                    close()
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "checkmark")
                            .opacity(option.isSelected ? 1 : 0)
                            .accessibilityHidden(true)
                        Text(option.title)
                        Spacer(minLength: 0)
                    }
                    .frame(width: 520, alignment: .leading)
                }
                .focused(focus, equals: .option(menu: menu.id, option: option.id))
                // The check, for VoiceOver.
                .accessibilityAddTraits(option.isSelected ? .isSelected : [])
                .accessibilityIdentifier("player.option.\(menu.id).\(option.id)")
            }
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .focusSection()
    }
}

/// Wholphin's round transport buttons: a quiet platter at rest and a light one when focused, in
/// the theme's colours.
struct OverlayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        OverlayButtonLabel(configuration: configuration)
    }

    private struct OverlayButtonLabel: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var isFocused
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.theme) private var theme

        var body: some View {
            configuration.label
                .font(.title3)
                .foregroundStyle(isFocused ? theme.onFocusedPlatter : theme.onPlatter)
                .frame(minWidth: 72, minHeight: 72)
                .padding(.horizontal, 8)
                .background(isFocused ? theme.focusedPlatter : theme.platter, in: Capsule())
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

    @Environment(\.theme) private var theme

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
        .accessibilityValue(spokenPosition)
        .accessibilityIdentifier(identifier)
    }

    /// "1 minute, 5 seconds of 10 minutes": where the bar is, and how long the video is.
    private var spokenPosition: Text {
        let position = seeker.shownPosition.spokenTime
        guard let duration = seeker.duration, duration > .zero else { return Text(position) }
        return Text("\(position) of \(duration.spokenTime)")
    }

    private var track: some View {
        VStack(spacing: 12) {
            GeometryReader { geometry in
                let height = geometry.size.height
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(theme.seekTrack)
                    Capsule()
                        .fill(theme.seekPlayed)
                        .frame(width: max(geometry.size.width * fraction, height))
                    Circle()
                        .fill(theme.seekPlayed)
                        .frame(width: height * 2.2, height: height * 2.2)
                        .offset(x: geometry.size.width * fraction - height * 1.1)
                        .opacity(isFocused || showsPreview ? 1 : 0)
                }
            }
            .frame(height: isFocused ? 12 : 6)
            .animation(.easeOut(duration: 0.15), value: isFocused)
            HStack {
                Text(seeker.shownPosition.clockText)
                Spacer()
                Text("-" + max((seeker.duration ?? .zero) - seeker.shownPosition, .zero).clockText)
            }
            .font(.callout.monospacedDigit())
            .foregroundStyle(theme.secondaryText)
        }
    }
}

/// When playback will end at the current speed, as Wholphin's "Ends at". It works it out again
/// every second, as Wholphin does, so it moves on while paused too, when the position doesn't;
/// on a schedule from a fixed moment, which a body run doesn't start again.
private struct EndTime: View {
    let seeker: Seeker
    let rate: Float

    @Environment(\.theme) private var theme

    var body: some View {
        if let duration = seeker.duration, duration > .zero {
            let remaining = max(duration - seeker.position, .zero) / Double(max(rate, 0.1))
            TimelineView(.everySecond) { context in
                remaining.endsAtText(from: context.date)
            }
            .font(.callout)
            .foregroundStyle(theme.secondaryText)
            .accessibilityIdentifier("player.endsAt")
        }
    }
}

/// The audio and subtitle tracks playing, as the engine lists them.
private struct TrackSummary: View {
    let playback: PlaybackController

    @Environment(\.theme) private var theme
    @State private var summary: String?

    var body: some View {
        Group {
            if let summary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
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
