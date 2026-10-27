import AnemonePlayback
import AnemoneUI
import AVFoundation
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
/// draws itself, such as MPV's.
final class PlayerVideoView: UIView {
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var output: PlayerVideoOutput? {
        didSet {
            show()
        }
    }

    private var hostedLayer: CALayer?

    private var playerLayer: AVPlayerLayer? {
        layer as? AVPlayerLayer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        hostedLayer?.frame = bounds
    }

    private func show() {
        hostedLayer?.removeFromSuperlayer()
        hostedLayer = nil
        playerLayer?.player = nil
        switch output {
        case let .avPlayer(player):
            playerLayer?.videoGravity = .resizeAspect
            playerLayer?.player = player
        case let .layer(engineLayer):
            engineLayer.frame = bounds
            layer.addSublayer(engineLayer)
            hostedLayer = engineLayer
        case nil:
            break
        }
    }
}
