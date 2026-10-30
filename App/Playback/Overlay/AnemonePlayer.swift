import AnemoneJellyfin
import AnemonePlayback
import AnemoneUI
import AVFoundation
import Combine
import SwiftUI
import UIKit

/// Anemone's own player: the engine's video under Wholphin's overlay, for when Settings asks for
/// it instead of the system player, and for engines like MPV that can't use the system player.
/// It drives playback only through the controller and its `PlayerEngine`.
struct AnemonePlayer: View {
    let playback: PlaybackController

    @Environment(BrowseModel.self) private var browse
    @Environment(\.dismiss) private var dismiss
    @State private var overlay: PlayerOverlay?

    var body: some View {
        Group {
            if let overlay {
                OverlayHost(playback: playback, overlay: overlay, browse: browse) {
                    dismiss()
                }
            } else {
                Color.black
            }
        }
        .onAppear {
            if overlay == nil {
                overlay = PlayerOverlay(controller: playback)
            }
            playback.feature(PlaybackDetails.self)?.loadSeekPreviews()
        }
    }
}

/// Hosts the video and the SwiftUI overlay in a view controller of its own, which sees the
/// remote's presses before the focus engine does. SwiftUI's move commands carry no press
/// lengths, so holding left or right to seek needs `pressesBegan` and `pressesEnded`.
private struct OverlayHost: UIViewControllerRepresentable {
    let playback: PlaybackController
    let overlay: PlayerOverlay
    let browse: BrowseModel
    let close: () -> Void

    func makeUIViewController(context _: Context) -> OverlayViewController {
        let content = OverlayView(playback: playback, overlay: overlay, session: browse.session)
            .environment(browse)
            .appTheme()
        return OverlayViewController(
            playback: playback,
            overlay: overlay,
            content: UIHostingController(rootView: AnyView(content)),
            close: close,
        )
    }

    func updateUIViewController(_ controller: OverlayViewController, context _: Context) {
        controller.close = close
    }
}

/// Wholphin's `PlaybackKeyHandler` on UIKit: hands the remote's presses and the touch surface's
/// sideways swipes to `PlayerOverlay`, and passes on what it leaves to the focus engine, as
/// Swiftfin's tvOS player container does.
final class OverlayViewController: UIViewController, UIGestureRecognizerDelegate {
    private let playback: PlaybackController
    private let overlay: PlayerOverlay
    private let content: UIHostingController<AnyView>
    private let videoView = PlayerVideoView()
    /// Holds focus while the controls are hidden, so presses come here.
    private let catcher = FocusCatcherView()
    /// Menu comes through this rather than `pressesBegan`, since the full-screen presentation
    /// recognizes Menu itself and would close the player on the first press.
    private lazy var menuTap = UITapGestureRecognizer(target: self, action: #selector(menuPressed))
    private var hasFollowed = false
    var close: () -> Void

    init(
        playback: PlaybackController,
        overlay: PlayerOverlay,
        content: UIHostingController<AnyView>,
        close: @escaping () -> Void,
    ) {
        self.playback = playback
        self.overlay = overlay
        self.content = content
        self.close = close
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        videoView.output = playback.engine.videoOutput
        // How UI tests tell this player from the system one.
        catcher.isAccessibilityElement = true
        catcher.accessibilityIdentifier = "player.overlay"
        for subview in [videoView, catcher] {
            subview.frame = view.bounds
            subview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(subview)
        }
        addChild(content)
        content.view.backgroundColor = .clear
        content.view.frame = view.bounds
        content.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(content.view)
        content.didMove(toParent: self)

        let swipe = UIPanGestureRecognizer(target: self, action: #selector(swiped))
        swipe.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        swipe.delegate = self
        view.addGestureRecognizer(swipe)
        menuTap.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
        menuTap.delegate = self
        view.addGestureRecognizer(menuTap)

        followOverlay()
        followVideoScale()
    }

    override var preferredFocusEnvironments: [any UIFocusEnvironment] {
        catcher.isOn ? [catcher] : [content]
    }

    /// The catcher takes focus while the controls are hidden and nothing else wants it: no
    /// feature's action over the video, and no card from the player screen.
    private func followOverlay() {
        let accessories = playback.accessories
        let wantsCatcher = withObservationTracking {
            !overlay.controlsVisible && accessories.actions.isEmpty && accessories.card == nil
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.followOverlay()
            }
        }
        guard wantsCatcher != catcher.isOn || !hasFollowed else { return }
        hasFollowed = true
        catcher.isOn = wantsCatcher
        // A card brings its own focus; asking for it here could take it away.
        guard accessories.card == nil else { return }
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
    }

    /// The video view follows the overlay's Video scale choice. For an engine that draws its
    /// own layer, which doesn't say how big the video is, the server's size for the stream
    /// stands in.
    private func followVideoScale() {
        let details = playback.feature(PlaybackDetails.self)
        let (scale, size) = withObservationTracking {
            (overlay.videoScale, details?.stream?.video.flatMap(Self.size))
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.followVideoScale()
            }
        }
        videoView.scale = scale
        videoView.fallbackVideoSize = size
    }

    private static func size(_ video: MediaVersion.Video) -> CGSize? {
        guard let width = video.width, let height = video.height, width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    // MARK: - Presses

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var passed = Set<UIPress>()
        for press in presses where press.type != .menu {
            guard let button = PlayerOverlay.Button(press.type) else {
                passed.insert(press)
                continue
            }
            if overlay.pressBegan(button) == .passedOn {
                passed.insert(press)
            }
        }
        if !passed.isEmpty {
            super.pressesBegan(passed, with: event)
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var passed = Set<UIPress>()
        for press in presses where press.type != .menu {
            guard let button = PlayerOverlay.Button(press.type) else {
                passed.insert(press)
                continue
            }
            switch overlay.pressEnded(button) {
            case .handled:
                break
            case .passedOn:
                passed.insert(press)
            case .close:
                close()
            }
        }
        if !passed.isEmpty {
            super.pressesEnded(passed, with: event)
        }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            if let button = PlayerOverlay.Button(press.type) {
                overlay.pressCancelled(button)
            }
        }
        super.pressesCancelled(presses.filter { $0.type != .menu }, with: event)
    }

    @objc private func menuPressed() {
        _ = overlay.pressBegan(.menu)
        if overlay.pressEnded(.menu) == .close {
            close()
        }
    }

    /// The presentation's own Menu handling waits for the overlay's, which always takes it.
    func gestureRecognizer(
        _ recognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy other: UIGestureRecognizer,
    ) -> Bool {
        recognizer === menuTap && other.allowedPressTypes.contains(NSNumber(value: UIPress.PressType.menu.rawValue))
    }

    // MARK: - Swipes

    /// Only sideways swipes, and only when the overlay scrubs with them; otherwise the focus
    /// engine gets them to move focus.
    func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard recognizer !== menuTap else { return true }
        guard let pan = recognizer as? UIPanGestureRecognizer, overlay.takesSwipes else { return false }
        let velocity = pan.velocity(in: view)
        return abs(velocity.x) > abs(velocity.y)
    }

    @objc private func swiped(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            overlay.swipeBegan()
        case .changed:
            overlay.swipeMoved(translation: pan.translation(in: view).x, width: view.bounds.width)
        case .ended, .cancelled, .failed:
            overlay.swipeEnded()
        default:
            break
        }
    }
}

private extension PlayerOverlay.Button {
    init?(_ type: UIPress.PressType) {
        switch type {
        case .upArrow: self = .upArrow
        case .downArrow: self = .downArrow
        case .leftArrow: self = .leftArrow
        case .rightArrow: self = .rightArrow
        case .select: self = .select
        case .menu: self = .menu
        case .playPause: self = .playPause
        default: return nil
        }
    }
}

/// An invisible view over the video that can hold focus, so the remote's presses reach the
/// overlay while there's nothing else to focus.
private final class FocusCatcherView: UIView {
    var isOn = false

    override var canBecomeFocused: Bool {
        isOn
    }
}

/// Where the engine's video shows: AVPlayer's through an `AVPlayerLayer`, or a layer the engine
/// draws itself, such as MPV's, placed on the screen as the overlay's Video scale says
/// (`VideoScale.frame`). AVPlayer says how big its video is; an engine's own layer doesn't, so
/// `fallbackVideoSize` stands in for it (the overlay offers such a layer only the choices that
/// need the picture's proportions). The screensaver counts a view with an `output` as a video
/// playing (`ScreensaverPresenter`).
final class PlayerVideoView: UIView {
    var output: PlayerVideoOutput? {
        didSet {
            show()
        }
    }

    /// How the video fills the screen.
    var scale = VideoScale.fit {
        didSet {
            setNeedsLayout()
        }
    }

    /// The video's size in pixels for an output that doesn't say, such as the server's.
    var fallbackVideoSize: CGSize? {
        didSet {
            setNeedsLayout()
        }
    }

    private var hostedLayer: CALayer?
    private var playerLayer: AVPlayerLayer?
    private var sizeWatcher: Task<Void, Never>?
    /// The loaded item's size, once AVPlayer knows it.
    private var presentedSize = CGSize.zero {
        didSet {
            setNeedsLayout()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        // A cropped picture runs past the edges.
        layer.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        // The publisher never ends on its own, and the task holds the player.
        sizeWatcher?.cancel()
    }

    private var videoSize: CGSize {
        playerLayer != nil ? presentedSize : fallbackVideoSize ?? .zero
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Fill stretches; the rest keep the picture in proportion within a frame of the
        // video's own, and Crop fills the screen while the size is still unknown.
        playerLayer?.videoGravity = switch scale {
        case .fill: .resize
        case .crop where videoSize == .zero: .resizeAspectFill
        default: .resizeAspect
        }
        // As a view's frame moves without animating.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // None counts the video's pixels against the screen's: 2 a point on a 4K Apple TV.
        let pixelsPerPoint = max(window?.screen.nativeScale ?? 1, 1)
        hostedLayer?.frame = scale.frame(video: videoSize, in: bounds.size, pixelsPerPoint: pixelsPerPoint)
        CATransaction.commit()
    }

    private func show() {
        hostedLayer?.removeFromSuperlayer()
        hostedLayer = nil
        playerLayer = nil
        sizeWatcher?.cancel()
        sizeWatcher = nil
        presentedSize = .zero
        switch output {
        case let .avPlayer(player):
            let playerLayer = AVPlayerLayer(player: player)
            self.playerLayer = playerLayer
            hostedLayer = playerLayer
            sizeWatcher = Task { [weak self] in
                for await size in player.publisher(for: \.currentItem?.presentationSize).values {
                    self?.presentedSize = size ?? .zero
                }
            }
        case let .layer(engineLayer):
            hostedLayer = engineLayer
        case nil:
            break
        }
        if let hostedLayer {
            hostedLayer.frame = bounds
            layer.addSublayer(hostedLayer)
        }
        setNeedsLayout()
    }
}
