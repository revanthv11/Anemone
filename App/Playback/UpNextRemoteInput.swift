import SwiftUI
import UIKit

/// Calls `onInput` for every press and touch on the Siri Remote while it's on screen, for Up
/// Next's pass-out protection. The system player keeps remote presses to itself, so this listens
/// at the window, where every press passes, and lets each one carry on.
struct RemoteInputObserver: UIViewRepresentable {
    let onInput: () -> Void

    func makeUIView(context _: Context) -> ObserverView {
        ObserverView(onInput: onInput)
    }

    func updateUIView(_ view: ObserverView, context _: Context) {
        view.onInput = onInput
    }

    final class ObserverView: UIView {
        var onInput: () -> Void
        private lazy var recognizer = InputRecognizer { [weak self] in
            self?.onInput()
        }

        init(onInput: @escaping () -> Void) {
            self.onInput = onInput
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        /// Listens at the window for as long as this view is in it.
        override func willMove(toWindow newWindow: UIWindow?) {
            super.willMove(toWindow: newWindow)
            recognizer.view?.removeGestureRecognizer(recognizer)
            newWindow?.addGestureRecognizer(recognizer)
        }
    }
}

/// Notes each press or touch, then fails at once, so it never takes one from the player.
private final class InputRecognizer: UIGestureRecognizer {
    private let onInput: () -> Void

    init(onInput: @escaping () -> Void) {
        self.onInput = onInput
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        allowedPressTypes = Self.pressTypes.map { NSNumber(value: $0.rawValue) }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        super.pressesBegan(presses, with: event)
        onInput()
        state = .failed
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        onInput()
        state = .failed
    }

    private static let pressTypes: [UIPress.PressType] = [
        .select,
        .playPause,
        .menu,
        .upArrow,
        .downArrow,
        .leftArrow,
        .rightArrow,
        .pageUp,
        .pageDown,
    ]
}
