import SwiftUI
import UIKit

/// Hears the remote's page up and page down buttons (channel up and down on TV remotes and
/// universal remotes) while this view is on screen, for Wholphin's paging through a grid with
/// the remote. SwiftUI has no handler for these presses, so a gesture recognizer on the window
/// catches them; the window sees every press, whichever view has focus.
struct RemotePageButtons: UIViewRepresentable {
    /// Called with `true` for page down, `false` for page up.
    let onPress: (_ forward: Bool) -> Void

    func makeUIView(context _: Context) -> PressCatcher {
        PressCatcher()
    }

    func updateUIView(_ view: PressCatcher, context _: Context) {
        view.onPress = onPress
    }

    final class PressCatcher: UIView, UIGestureRecognizerDelegate {
        var onPress: (Bool) -> Void = { _ in }
        private lazy var pageUp = recognizer(for: .pageUp)
        private lazy var pageDown = recognizer(for: .pageDown)

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            for recognizer in [pageUp, pageDown] {
                recognizer.view?.removeGestureRecognizer(recognizer)
                window?.addGestureRecognizer(recognizer)
            }
        }

        private func recognizer(for press: UIPress.PressType) -> UITapGestureRecognizer {
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(pressed))
            recognizer.allowedPressTypes = [NSNumber(value: press.rawValue)]
            recognizer.allowedTouchTypes = []
            recognizer.delegate = self
            return recognizer
        }

        @objc private func pressed(_ recognizer: UITapGestureRecognizer) {
            onPress(recognizer === pageDown)
        }

        /// Another grid's catcher can be in the window too, such as one under a pushed page; each
        /// hears the press, and only the one with focus acts on it.
        func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer,
        ) -> Bool {
            true
        }
    }
}
