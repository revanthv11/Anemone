import AnemoneJellyfin
import AnemonePlayback
import AnemoneUI
import AVFoundation
import SwiftUI

/// What opens the slideshow: which photos, the one picked, and whether it starts running.
struct SlideshowStart: Identifiable {
    let id = UUID()
    let query: SlideshowQuery
    /// The photo picked in a grid; the first when `nil`.
    var itemID: MediaItem.ID?
    /// Where it was in the grid, near where it is in the slideshow.
    var gridIndex = 0
    /// Play and Shuffle start the slideshow; picking a photo opens the viewer.
    var runs = false
}

/// Wholphin's `SlideshowPage`: one photo at a time, full screen. Left and right move through
/// the photos; Select, up or down show the details and controls, which pause a running
/// slideshow; Back hides them, then leaves. Zoomed in, the arrows move around the photo and Back
/// zooms out. Play/Pause starts and stops the slideshow, or pauses a clip.
struct SlideshowView: View {
    let start: SlideshowStart

    @Environment(BrowseModel.self) private var browse
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var slideshow: Slideshow?
    @State private var problem: String?
    @State private var showsDetails = false
    @State private var framing = PhotoFraming()
    @State private var notice: Notice?
    @State private var clip: ClipPlayer?
    @FocusState private var isPhotoFocused: Bool

    /// What Wholphin says in a toast, such as at the last photo.
    private struct Notice: Equatable {
        let id = UUID()
        let text: String
    }

    var body: some View {
        ZStack {
            Color.black
            if let slideshow {
                photo(in: slideshow)
                if showsDetails {
                    SlideshowDetails(
                        slideshow: slideshow,
                        clip: clip,
                        framing: $framing,
                        toggleSlideshow: { toggleSlideshow(slideshow) },
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onExitCommand {
                        hideDetails(slideshow)
                    }
                }
            } else if let problem {
                VStack(spacing: 40) {
                    Text(problem)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("OK") { dismiss() }
                }
            } else {
                ProgressView()
            }
            if let notice {
                VStack {
                    Text(notice.text)
                        .font(.callout)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 16)
                        .background(.regularMaterial, in: .capsule)
                        .padding(.top, 60)
                        .accessibilityIdentifier("slideshow.notice")
                    Spacer()
                }
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.25), value: showsDetails)
        .animation(.easeInOut(duration: 0.25), value: notice)
        .task {
            await load()
        }
        .task(id: notice) {
            guard notice != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            notice = nil
        }
        .onChange(of: slideshow?.isRunning) { _, isRunning in
            // Like Wholphin, keeps the screen on while the slideshow runs.
            UIApplication.shared.isIdleTimerDisabled = isRunning == true
            // A clip plays once in a running slideshow, over and over in the viewer.
            clip?.loops = isRunning != true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            slideshow?.stopSlideshow()
            clip?.stop()
        }
    }

    private func photo(in slideshow: Slideshow) -> some View {
        let item = slideshow.current
        // A button, so Select reaches it; it draws nothing of its own.
        return Button {
            showDetails(slideshow)
        } label: {
            ZStack {
                if let item, item.kind == .video, let clip {
                    ClipView(player: clip.player)
                    if clip.hasFailed {
                        Text("Couldn't play this clip.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    SlideshowPhoto(url: photoURL(item)) { loaded in
                        if loaded {
                            slideshow.photoShown()
                        } else if let item {
                            slideshow.itemFailed(item.id)
                        }
                    }
                }
            }
            // Turned first, so zooming and moving around work on the screen as it shows.
            .rotationEffect(.degrees(framing.rotation))
            .scaleEffect(framing.zoom)
            .offset(framing.pan)
            .animation(.easeInOut(duration: 0.3), value: framing)
        }
        .buttonStyle(BareButtonStyle())
        // Focus goes to the details while they show.
        .disabled(showsDetails)
        .focused($isPhotoFocused)
        .defaultFocus($isPhotoFocused, true)
        .onMoveCommand { direction in
            move(direction, in: slideshow)
        }
        .onExitCommand(perform: framing.isZoomed ? { framing.fit() } : nil)
        .onPlayPauseCommand {
            if let clip, item?.kind == .video {
                clip.togglePause()
            } else {
                toggleSlideshow(slideshow)
            }
        }
        .accessibilityLabel(item?.name ?? "Photo")
        .accessibilityIdentifier("slideshow.photo")
        .onChange(of: item?.id) {
            framing = PhotoFraming()
            prepare(item, in: slideshow)
        }
    }

    private func photoURL(_ item: SlideshowItem?) -> URL? {
        // As wide as the screen in pixels; the server keeps smaller photos as they are.
        browse.imageURL(item?.image, width: 1920 * displayScale)
    }

    private func load() async {
        let query = start.query
        // A random order is shuffled once for the whole slideshow, with the photo picked first.
        let isShuffled = query.sort.field == .random
        let pager = SlideshowPager(loader: browse.session.slideshowLoader(for: query, first: start.itemID))
        let slideshow = Slideshow(pager: pager, delay: Slideshow.delay())
        do {
            try await slideshow.load(showing: start.itemID, near: isShuffled ? 0 : start.gridIndex)
            guard pager.count > 0 else {
                problem = "There are no photos here."
                return
            }
            self.slideshow = slideshow
            if start.runs {
                slideshow.startSlideshow()
            }
            prepare(slideshow.current, in: slideshow)
        } catch {
            problem = browse.problem(with: error, doing: "load the photos from \(browse.server.name)")
        }
    }

    /// Plays a clip that comes up, and fetches the photos either side ahead.
    private func prepare(_ item: SlideshowItem?, in slideshow: Slideshow) {
        clip?.stop()
        clip = nil
        if let item, item.kind == .video, let url = browse.session.slideshowClipURL(for: item.id) {
            let clip = ClipPlayer(url: url) { [weak slideshow] event in
                switch event {
                case let .playing(length): slideshow?.clipPlaying(length: length)
                case .ended: slideshow?.clipEnded()
                case .failed: slideshow?.itemFailed(item.id)
                }
            }
            clip.loops = !slideshow.isRunning
            self.clip = clip
            slideshow.clipStarted()
            clip.play()
        }
        let neighbours = [slideshow.position + 1, slideshow.position - 1]
            .compactMap { slideshow.pager.item(at: $0) }
            .filter { $0.kind == .photo }
            .compactMap(photoURL)
        SlideshowPhoto.prefetch(neighbours)
    }

    private func move(_ direction: MoveCommandDirection, in slideshow: Slideshow) {
        if framing.isZoomed {
            framing.pan(direction)
        } else {
            switch direction {
            case .left:
                if !slideshow.previous() {
                    notice = Notice(text: "At beginning")
                }
            case .right:
                if !slideshow.next() {
                    notice = Notice(text: "No more photos")
                }
            default:
                showDetails(slideshow)
                return
            }
        }
        // As in Wholphin, a press counts the time again.
        slideshow.restartTime()
    }

    private func showDetails(_ slideshow: Slideshow) {
        showsDetails = true
        slideshow.pause()
    }

    private func hideDetails(_ slideshow: Slideshow) {
        showsDetails = false
        isPhotoFocused = true
        slideshow.resume()
    }

    /// Wholphin's Play slideshow and Stop slideshow. Starting it hides the details.
    private func toggleSlideshow(_ slideshow: Slideshow) {
        if slideshow.isRunning {
            slideshow.stopSlideshow()
        } else {
            showsDetails = false
            isPhotoFocused = true
            slideshow.startSlideshow()
        }
    }
}

/// How the photo showing is turned and zoomed, as Wholphin's slideshow allows: up to five times,
/// moving around it while zoomed in. A new photo starts afresh.
struct PhotoFraming: Equatable {
    var zoom: CGFloat = 1
    var rotation: Double = 0
    var pan = CGSize.zero

    /// Wholphin's zoom step and limits.
    static let zoomStep: CGFloat = 0.15
    static let zoomRange: ClosedRange<CGFloat> = 1 ... 5
    /// Wholphin moves 30 dp a press, doubled for a 1920-point screen, up to 75% of the screen.
    static let panStep: CGFloat = 60
    static let panLimit = CGSize(width: 1920 * 0.75, height: 1080 * 0.75)

    var isZoomed: Bool {
        zoom > 1.02
    }

    mutating func zoom(by step: CGFloat) {
        let old = zoom
        zoom = min(max(zoom + step, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        if !isZoomed {
            pan = .zero
        } else if zoom < old {
            // Zooming out brings the view back towards the middle, as Wholphin's does.
            let scale = (zoom - 1) / (old - 1)
            pan = CGSize(width: pan.width * scale, height: pan.height * scale)
        }
    }

    /// Back to the whole photo, keeping its turn, as Back does in Wholphin.
    mutating func fit() {
        zoom = 1
        pan = .zero
    }

    mutating func rotate(by degrees: Double) {
        rotation += degrees
    }

    /// Moves the view, so the photo goes the other way, as the arrows do in Wholphin.
    mutating func pan(_ direction: MoveCommandDirection) {
        switch direction {
        case .left: pan.width = min(pan.width + Self.panStep, Self.panLimit.width)
        case .right: pan.width = max(pan.width - Self.panStep, -Self.panLimit.width)
        case .up: pan.height = min(pan.height + Self.panStep, Self.panLimit.height)
        case .down: pan.height = max(pan.height - Self.panStep, -Self.panLimit.height)
        @unknown default: break
        }
    }
}

/// A button that shows its label as it is, without the focus effect.
private struct BareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
