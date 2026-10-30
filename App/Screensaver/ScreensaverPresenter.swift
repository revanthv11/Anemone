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
                    screensaver.isOnScreen = { [weak stage] in stage?.isOnScreen ?? false }
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
        let content = ScreensaverView(session: session, showsSlides: screensaver.showsSlides)
        let controller = ScreensaverController(content: content) { [screensaver] in
            screensaver.stop()
        }
        controller.removed = { [weak controller, stage, screensaver] in
            // Taken away without a press, along with what it was shown over, as when a sheet
            // under it is dismissed: it can show again after the delay.
            guard let controller, stage.shown === controller else { return }
            stage.shown = nil
            screensaver.stop()
        }
        stage.shown = controller
        top.present(controller, animated: true)
        // UIKit refuses to present over a controller that's on its way out, or already
        // presenting, and only logs it.
        if controller.presentingViewController == nil {
            stage.shown = nil
            screensaver.stop()
        }
    }

    private func dismiss() {
        guard let controller = stage.shown else { return }
        stage.shown = nil
        if controller.presentingViewController != nil {
            controller.dismiss(animated: true)
        }
    }

    /// Whether a video is on screen, like Wholphin's `keepScreenOn` during playback: a player
    /// presented over the app, either the system one or Anemone's overlay (its `PlayerVideoView`
    /// with a picture in it, MPV's included), or anything that turned off the system's idle timer.
    private static func keepsScreenOn(in window: UIWindow?) -> Bool {
        if UIApplication.shared.isIdleTimerDisabled {
            return true
        }
        var controller = window?.rootViewController?.presentedViewController
        while let current = controller {
            if current.containsPlayer || current.viewIfLoaded?.containsVideo == true {
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

    /// Whether the screensaver shown is still presented, even if something covers it.
    var isOnScreen: Bool {
        shown?.presentingViewController != nil
    }
}

private extension UIViewController {
    var containsPlayer: Bool {
        self is AVPlayerViewController || children.contains { $0.containsPlayer }
    }
}

private extension UIView {
    /// The player's video view with an engine's picture in it (its `AVPlayerLayer` or MPV's layer
    /// is a sublayer of its own), an `AVPlayerLayer` anywhere else, or a view holding either.
    var containsVideo: Bool {
        (self as? PlayerVideoView)?.output != nil || layer is AVPlayerLayer || subviews.contains { $0.containsVideo }
    }
}

/// Shows the screensaver full screen. It holds focus while it shows, so the first press or
/// touch closes it and goes no further.
private final class ScreensaverController: UIViewController {
    /// Called once it's no longer presented, however it went.
    var removed: () -> Void = {}
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
        // The view draws black behind its pictures; dimming alone shows the app through it.
        view.backgroundColor = .clear
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

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Gone, rather than covered by something shown over it. UIKit may finish taking it out
        // of the presentation only after this, so it's checked again once this turn is over.
        if isBeingDismissed || presentingViewController == nil {
            removed()
        } else {
            Task { [weak self] in
                if let self, presentingViewController == nil {
                    removed()
                }
            }
        }
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
