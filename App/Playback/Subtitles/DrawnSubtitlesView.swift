import AnemonePlayback
import SwiftUI

/// Draws the text subtitles at the playing position (`DrawnSubtitles`) over either player's
/// video, in the user's subtitle style, as Wholphin's subtitle view draws ExoPlayer's. Over
/// Anemone's overlay they move up above its controls while those show.
///
/// The style's sizes come out as MPV draws them (`SubtitleStyle.mpvProperties`): a font size of
/// 24 is about 48 points of text on the 1080-point screen, and an edge size of 4 is an outline of
/// about 5 points. The margin is a share of the screen's height, as in Wholphin.
struct DrawnSubtitlesView: View {
    let playback: PlaybackController
    /// Anemone's overlay, whose controls the subtitles stay above; `nil` for the system player.
    var overlay: PlayerOverlay?

    var body: some View {
        if let subtitles = playback.feature(DrawnSubtitles.self) {
            SubtitleCues(subtitles: subtitles, clearance: clearance)
                .task(id: subtitles.track) {
                    guard subtitles.track != nil else { return }
                    await subtitles.follow()
                }
        }
    }

    /// How far up from the bottom the overlay's controls reach while they show.
    private var clearance: CGFloat {
        guard let overlay else { return 0 }
        if overlay.controlsVisible {
            return overlay.page == .controls ? 400 : 560
        }
        return overlay.showsSeekBar ? 240 : 0
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
