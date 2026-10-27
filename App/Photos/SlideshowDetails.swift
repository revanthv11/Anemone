import AnemoneJellyfin
import AnemonePlayback
import AnemoneUI
import SwiftUI

/// Wholphin's `ImageDetailsHeader` and `ImageControlsOverlay`, along the bottom of the photo:
/// its name, date, place in the slideshow, size and description, then Play or Stop slideshow
/// and, for a photo, turning and zooming it; for a clip, pausing it. Focus starts on the
/// slideshow button.
struct SlideshowDetails: View {
    let slideshow: Slideshow
    let clip: ClipPlayer?
    @Binding var framing: PhotoFraming
    let toggleSlideshow: () -> Void

    @Environment(\.theme) private var theme
    @FocusState private var isSlideshowButtonFocused: Bool

    var body: some View {
        let item = slideshow.current
        VStack(alignment: .leading, spacing: 16) {
            Text(item?.name ?? "")
                .font(.title2.bold())
                .foregroundStyle(theme.onBackground)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("slideshow.title")
            HStack(spacing: 24) {
                Text("\(slideshow.position + 1) of \(slideshow.pager.count)")
                    .accessibilityIdentifier("slideshow.position")
                if let date = item?.date {
                    Text(date.formatted(date: .long, time: .omitted))
                }
                if let width = item?.width, let height = item?.height {
                    Text(verbatim: "\(width)×\(height)")
                        .accessibilityLabel("\(width) by \(height) pixels")
                }
            }
            .font(.callout)
            .foregroundStyle(theme.secondaryText)
            if let overview = item?.overview, !overview.isEmpty {
                Text(overview)
                    .font(.callout)
                    .foregroundStyle(theme.onBackground)
                    .lineLimit(3)
                    .frame(maxWidth: 1200, alignment: .leading)
            }
            HStack(spacing: 24) {
                ActionButton(
                    title: slideshow
                        .isRunning ? String(localized: "Stop slideshow") : String(localized: "Play slideshow"),
                    systemImage: slideshow.isRunning ? "pause.fill" : "play.fill",
                    action: toggleSlideshow,
                )
                .focused($isSlideshowButtonFocused)
                .accessibilityValue(slideshow.isRunning ? "Playing" : "Stopped")
                .accessibilityIdentifier("slideshow.toggle")
                if item?.kind == .video, let clip {
                    ActionButton(
                        title: clip.isPaused ? String(localized: "Play") : String(localized: "Pause"),
                        systemImage: clip.isPaused ? "play" : "pause",
                    ) {
                        clip.togglePause()
                    }
                    .accessibilityValue(clip.isPaused ? "Paused" : "Playing")
                    .accessibilityIdentifier("slideshow.clip")
                } else {
                    photoControls
                }
            }
            .padding(.top, 8)
            .focusSection()
        }
        .padding(.horizontal, 80)
        .padding(.top, 60)
        .padding(.bottom, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .background(alignment: .bottom) {
            LinearGradient(colors: [.clear, theme.scrim.withAlpha(0.8).color], startPoint: .top, endPoint: .bottom)
                .frame(height: 520)
        }
        .defaultFocus($isSlideshowButtonFocused, true)
        // The page's default focus was settled when the viewer opened, so it's moved here.
        .onAppear {
            isSlideshowButtonFocused = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("slideshow.details")
    }

    @ViewBuilder
    private var photoControls: some View {
        ActionButton(title: String(localized: "Rotate left"), systemImage: "rotate.left") {
            framing.rotate(by: -90)
        }
        .accessibilityIdentifier("slideshow.rotateLeft")
        ActionButton(title: String(localized: "Rotate right"), systemImage: "rotate.right") {
            framing.rotate(by: 90)
        }
        .accessibilityIdentifier("slideshow.rotateRight")
        ActionButton(title: String(localized: "Zoom in"), systemImage: "plus.magnifyingglass") {
            framing.zoom(by: PhotoFraming.zoomStep)
        }
        .accessibilityIdentifier("slideshow.zoomIn")
        ActionButton(title: String(localized: "Zoom out"), systemImage: "minus.magnifyingglass") {
            framing.zoom(by: -PhotoFraming.zoomStep)
        }
        .accessibilityIdentifier("slideshow.zoomOut")
        ActionButton(title: String(localized: "Reset"), systemImage: "arrow.counterclockwise") {
            framing = PhotoFraming()
        }
        .accessibilityIdentifier("slideshow.reset")
    }
}
