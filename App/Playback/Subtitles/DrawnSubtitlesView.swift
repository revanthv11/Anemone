import AnemonePlayback
import AVKit
import SwiftUI

/// Draws the text subtitles at the playing position (`DrawnSubtitles`) over either player's
/// video, in the user's subtitle style, as Wholphin's subtitle view draws ExoPlayer's. They move
/// up above Anemone's controls, or the system player's transport bar, while those show.
///
/// The style's sizes come out as MPV draws them (`SubtitleStyle.mpvProperties`): a font size of
/// 24 is about 48 points of text on the 1080-point screen, and an edge size of 4 is an outline of
/// about 5 points. The margin is a share of the screen's height, as in Wholphin.
struct DrawnSubtitlesView: View {
    let playback: PlaybackController
    /// Anemone's overlay, whose controls the subtitles stay above; `nil` for the system player.
    var overlay: PlayerOverlay?

    @State private var showsTransportBar = false

    var body: some View {
        if let subtitles = playback.feature(DrawnSubtitles.self) {
            SubtitleCues(subtitles: subtitles, clearance: clearance)
                .task(id: subtitles.track) {
                    guard subtitles.track != nil else { return }
                    await subtitles.follow()
                }
                .background {
                    if overlay == nil, case let .avPlayer(player) = playback.engine.videoOutput {
                        TransportBarWatcher(player: player, isVisible: $showsTransportBar)
                    }
                }
        }
    }

    /// How far up from the bottom the controls reach while they show.
    private var clearance: CGFloat {
        guard let overlay else { return showsTransportBar ? 320 : 0 }
        guard overlay.controlsVisible else { return overlay.showsSeekBar ? 240 : 0 }
        guard overlay.page == .controls else { return 560 }
        // The controls are taller with the Chapters or Queue title under them.
        let chapters = playback.feature(PlaybackDetails.self)?.previews?.chapters ?? []
        return chapters.isEmpty && playback.queue.upcoming.isEmpty ? 400 : 480
    }
}

/// Says when the system player's transport bar shows, so the subtitles can move above it as the
/// player's own do. AVKit tells only its controller's delegate, which Anemone doesn't otherwise
/// set: this finds the system player showing `player` and becomes its delegate, unless something
/// else already is (then the subtitles stay where they are).
private struct TransportBarWatcher: UIViewRepresentable {
    let player: AVPlayer
    @Binding var isVisible: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isVisible: $isVisible)
    }

    func makeUIView(context: Context) -> FinderView {
        FinderView(player: player, delegate: context.coordinator)
    }

    func updateUIView(_: FinderView, context: Context) {
        context.coordinator.isVisible = $isVisible
    }

    @MainActor
    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        var isVisible: Binding<Bool>

        init(isVisible: Binding<Bool>) {
            self.isVisible = isVisible
        }

        func playerViewController(
            _: AVPlayerViewController,
            willTransitionToVisibilityOfTransportBar visible: Bool,
            with coordinator: any AVPlayerViewControllerAnimationCoordinator,
        ) {
            let isVisible = isVisible
            coordinator.addCoordinatedAnimations({ isVisible.wrappedValue = visible }, completion: nil)
        }
    }

    /// Looks for the player's controller among the view controllers shown, once it's in a window.
    final class FinderView: UIView {
        private let player: AVPlayer
        private weak var delegate: Coordinator?
        private var isAttached = false

        init(player: AVPlayer, delegate: Coordinator) {
            self.player = player
            self.delegate = delegate
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            attach()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            attach()
        }

        private func attach() {
            guard !isAttached, let root = window?.rootViewController,
                  let controller = Self.controller(showing: player, from: root)
            else { return }
            isAttached = true
            if controller.delegate == nil {
                controller.delegate = delegate
            }
        }

        private static func controller(
            showing player: AVPlayer,
            from controller: UIViewController,
        ) -> AVPlayerViewController? {
            if let playerController = controller as? AVPlayerViewController, playerController.player === player {
                return playerController
            }
            for child in controller.children {
                if let found = Self.controller(showing: player, from: child) {
                    return found
                }
            }
            return controller.presentedViewController.flatMap { Self.controller(showing: player, from: $0) }
        }
    }
}

/// The cues at the bottom of the screen, and those placed at the top (signs, mostly) there.
private struct SubtitleCues: View {
    let subtitles: DrawnSubtitles
    let clearance: CGFloat

    var body: some View {
        let style = subtitles.style
        let cues = subtitles.cues
        GeometryReader { geometry in
            let margin = geometry.size.height * CGFloat(style.margin) / 100
            let width = geometry.size.width * 0.85
            VStack(spacing: 0) {
                CueBlock(lines: cues.filter { $0.placement == .top }.flatMap(\.lines), style: style)
                    .frame(maxWidth: width)
                    .padding(.top, margin)
                Spacer(minLength: 0)
                CueBlock(lines: cues.filter { $0.placement == .bottom }.flatMap(\.lines), style: style)
                    .frame(maxWidth: width)
                    .padding(.bottom, max(margin, clearance))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.25), value: clearance)
        // For UI tests: what shows, read like a caption.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cues.map(\.text).joined(separator: "\n"))
        .accessibilityIdentifier("player.subtitles")
    }
}

/// Lines of text, each centred, in one box when the style asks for one.
private struct CueBlock: View {
    let lines: [SubtitleLine]
    let style: SubtitleStyle

    var body: some View {
        if !lines.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    StyledLine(line: line, style: style)
                }
            }
            .padding(style.background == .boxed ? style.fontPoints * 0.3 : 0)
            .background(style.background == .boxed ? style.backgroundTint : .clear)
        }
    }
}

/// A line in the style: its colour and opacity, with an outline or drop shadow, and its own box
/// when the style puts one behind each line.
private struct StyledLine: View {
    let line: SubtitleLine
    let style: SubtitleStyle

    var body: some View {
        let text = Text(attributed)
        ZStack {
            if style.edge == .solid {
                // Copies of the text all around it, in the edge colour, make the outline.
                ForEach(Array(outline.enumerated()), id: \.offset) { _, offset in
                    text.foregroundStyle(style.edgeTint).offset(offset)
                }
            }
            text.foregroundStyle(style.fontTint)
        }
        .shadow(
            color: style.edge == .shadow ? style.edgeTint : .clear,
            radius: style.edgePoints / 2,
            x: style.edgePoints / 2,
            y: style.edgePoints / 2,
        )
        .multilineTextAlignment(.center)
        .padding(.horizontal, style.background == .wrap ? style.fontPoints * 0.2 : 0)
        .background(style.background == .wrap ? style.backgroundTint : .clear)
    }

    /// The spans, bold or italic as the file or the style says.
    private var attributed: AttributedString {
        var result = AttributedString()
        for span in line.spans {
            var part = AttributedString(span.text)
            var font = Font.system(size: style.fontPoints, weight: style.isBold || span.isBold ? .bold : .regular)
            if style.isItalic || span.isItalic {
                font = font.italic()
            }
            part.font = font
            result += part
        }
        return result
    }

    /// Sixteen directions at the edge's width; eight for a thin one.
    private var outline: [CGSize] {
        let radius = style.edgePoints
        let count = radius <= 3 ? 8 : 16
        return (0 ..< count).map { step in
            let angle = Double(step) / Double(count) * 2 * .pi
            return CGSize(width: cos(angle) * radius, height: sin(angle) * radius)
        }
    }
}

private extension SubtitleStyle {
    /// The font's size in points: twice Wholphin's size, as MPV's text comes out.
    var fontPoints: CGFloat {
        CGFloat(fontSize) * 2
    }

    /// The outline's width in points, as MPV draws it: 1.2 times Wholphin's edge size.
    var edgePoints: CGFloat {
        CGFloat(edgeThickness) * 1.2
    }

    var fontTint: Color {
        fontColor.tint(opacity: fontOpacity)
    }

    /// The edge fades with the text, as in Wholphin.
    var edgeTint: Color {
        edgeColor.tint(opacity: fontOpacity)
    }

    var backgroundTint: Color {
        backgroundColor.tint(opacity: backgroundOpacity)
    }
}

private extension SubtitleColor {
    func tint(opacity: Int) -> Color {
        Color(
            red: Double(rgb >> 16 & 0xFF) / 255,
            green: Double(rgb >> 8 & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
        )
        .opacity(Double(min(max(opacity, 0), 100)) / 100)
    }
}
