import AnemoneJellyfin
import AVKit
import SwiftUI
import UIKit.UIGestureRecognizerSubclass

extension View {
    /// Runs the in-app screensaver while a profile is signed in: watches the remote for presses
    /// and touches, and shows the screensaver over everything on screen, sheets included, as
    /// Wholphin draws it over the whole app. The first press only closes it, like Wholphin's
    /// `dispatchKeyEvent`; focus is back where it was.
    func screensaver(_ screensaver: Screensaver, session: JellyfinSession?) -> some View {
        modifier(ScreensaverPresenter(screensaver: screensaver, session: session))
    }
}

private struct ScreensaverPresenter: ViewModifier {
    let screensaver: Screensaver
    let session: JellyfinSession?

    @Environment(\.scenePhase) private var scenePhase
    @State private var stage = ScreensaverStage()

    func body(content: Content) -> some View {
        content
            .background {
                RemoteActivityWatcher { [screensaver] in
                    screensaver.noteActivity()
                } windowChanged: { [stage, screensaver] window in
                    // SwiftUI may add a new watcher before taking the old one out of the window.
                    guard let window else { return }
                    stage.window = window
                    screensaver.keepsScreenOn = { [weak window] in Self.keepsScreenOn(in: window) }
                }
            }
            .task(id: session.map { "\($0.serverURL)/\($0.userID)" }) {
                guard session != nil else { return }
                await screensaver.run()
            }
            .onChange(of: screensaver.isShowing) { _, isShowing in
                if isShowing {
                    present()
                } else {
                    dismiss()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    screensaver.stop()
                }
            }
            .onChange(of: session == nil) { _, signedOut in
                if signedOut {
                    screensaver.stop()
                }
            }
    }

    private func present() {
        // Already showing, unless something else took it off screen.
        if let shown = stage.shown, shown.presentingViewController != nil {
            return
        }
        guard let session, var top = stage.window?.rootViewController else {
            screensaver.stop()
            return
        }
        while let next = top.presentedViewController, !next.isBeingDismissed {
            top = next
        }
        let controller = ScreensaverController(content: ScreensaverView(session: session)) { [screensaver] in
            screensaver.stop()
        }
        stage.shown = controller
        top.present(controller, animated: true)
    }

    private func dismiss() {
        guard let controller = stage.shown else { return }
        stage.shown = nil
        if controller.presentingViewController != nil {
            controller.dismiss(animated: true)
        }
    }

    /// Whether a video is on screen: the system player anywhere in what's presented, or anything
    /// that turned off the system's idle timer, as a player does.
    private static func keepsScreenOn(in window: UIWindow?) -> Bool {
        if UIApplication.shared.isIdleTimerDisabled {
            return true
        }
        var controller = window?.rootViewController
        while let current = controller {
            if current.containsPlayer {
                return true
            }
            controller = current.presentedViewController
        }
        return false
    }
}

/// The window the app is in, and the screensaver on screen. UIKit hands these over, so they're
/// kept outside SwiftUI's state.
private final class ScreensaverStage {
    weak var window: UIWindow?
    var shown: UIViewController?
}

private extension UIViewController {
    var containsPlayer: Bool {
        self is AVPlayerViewController || children.contains { $0.containsPlayer }
    }
}

/// Shows the screensaver full screen. It holds focus while it shows, so the first press or
/// touch closes it and goes no further.
private final class ScreensaverController: UIViewController {
    private let content: UIHostingController<ScreensaverView>
    private let close: () -> Void

    init(content: ScreensaverView, close: @escaping () -> Void) {
        self.content = UIHostingController(rootView: content)
        self.close = close
        super.init(nibName: nil, bundle: nil)
        // Over the page, so what's under it stays as it is.
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        view = FocusHolder()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.accessibilityIdentifier = "screensaver"
        addChild(content)
        content.view.frame = view.bounds
        content.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        content.view.backgroundColor = .clear
        view.addSubview(content.view)
        content.didMove(toParent: self)
    }

    override var preferredFocusEnvironments: [any UIFocusEnvironment] {
        [view]
    }

    override func pressesBegan(_: Set<UIPress>, with _: UIPressesEvent?) {
        close()
    }

    override func pressesEnded(_: Set<UIPress>, with _: UIPressesEvent?) {}

    override func pressesChanged(_: Set<UIPress>, with _: UIPressesEvent?) {}

    override func pressesCancelled(_: Set<UIPress>, with _: UIPressesEvent?) {}

    override func touchesBegan(_: Set<UITouch>, with _: UIEvent?) {
        close()
    }
}

/// A view that takes focus without drawing a focus effect.
private final class FocusHolder: UIView {
    override var canBecomeFocused: Bool {
        true
    }
}

/// Tells about every press and touch on the remote anywhere in the window, without getting in
/// the way of what they do.
private struct RemoteActivityWatcher: UIViewRepresentable {
    let activity: () -> Void
    let windowChanged: (UIWindow?) -> Void

    func makeUIView(context _: Context) -> WatcherView {
        WatcherView(activity: activity, windowChanged: windowChanged)
    }

    func updateUIView(_: WatcherView, context _: Context) {}

    final class WatcherView: UIView {
        private let recognizer: ActivityRecognizer
        private let windowChanged: (UIWindow?) -> Void

        init(activity: @escaping () -> Void, windowChanged: @escaping (UIWindow?) -> Void) {
            recognizer = ActivityRecognizer(activity: activity)
            self.windowChanged = windowChanged
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            recognizer.view?.removeGestureRecognizer(recognizer)
            window?.addGestureRecognizer(recognizer)
            windowChanged(window)
        }
    }
}

/// Notes the start of every press and touch, then fails at once, so the press or touch goes on
/// to the focused view as usual.
private final class ActivityRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private let activity: () -> Void

    init(activity: @escaping () -> Void) {
        self.activity = activity
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func pressesBegan(_: Set<UIPress>, with _: UIPressesEvent) {
        activity()
        state = .failed
    }

    override func touchesBegan(_: Set<UITouch>, with _: UIEvent) {
        activity()
        state = .failed
    }

    func gestureRecognizer(
        _: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer,
    ) -> Bool {
        true
    }
}
