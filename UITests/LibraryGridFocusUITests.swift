import XCTest

/// Down from a library grid's header buttons reaches its cards, however few there are, and Up
/// from the first row comes back. The header's buttons sit on the right, so a grid of less than
/// a row has nothing under them; tvOS on its own moves down only to what's below. Runs on the
/// Phase 2b spike's synthetic library (`-libraryGridSpike <count>`), which needs no server.
@MainActor
final class LibraryGridFocusUITests: XCTestCase {
    /// The spike header's buttons, left to right.
    private let buttons = ["Sort", "Filter"]

    override func setUp() {
        continueAfterFailure = true
    }

    func testDownFromTheHeaderReachesTheCards() {
        for count in [1, 2, 500] {
            let app = launchAnemone(arguments: ["-libraryGridSpike", "\(count)"])
            XCTAssertTrue(app.staticTexts["grid.position"].waitForExistence(timeout: 10), "\(count): grid appears")
            guard focusHeader(in: app) else {
                attachScreenshot(app, name: "\(count) no header")
                XCTFail("\(count): couldn't reach the header (focus on \(focusedIdentifier(in: app)))")
                continue
            }
            for button in buttons {
                XCTAssertTrue(moveAlongHeader(to: button, in: app), "\(count): \(button) takes focus")
                press(.down)
                let below = settledFocus(in: app)
                print("[check] \(count) items: Down from \(button) -> \(below)")
                attachScreenshot(app, name: "\(count) down from \(button)")
                guard below.hasPrefix("grid.card.") else {
                    // Focus stayed on the button, so the next one is still a press away.
                    XCTFail("\(count): Down from \(button) reaches a card (focus on \(below))")
                    continue
                }
                press(.up)
                let above = headerButton(in: app)
                print("[check] \(count) items: Up from \(below) -> \(above ?? focusedIdentifier(in: app))")
                XCTAssertNotNil(above, "\(count): Up from the first row returns to the header")
            }
            app.terminate()
        }
    }

    /// The header button with focus, if one has it.
    private func headerButton(in app: XCUIApplication) -> String? {
        _ = settledFocus(in: app)
        return buttons.first { app.buttons[$0].hasFocus }
    }

    /// Moves focus to the header from wherever it starts: the sidebar, a card or the alphabet bar.
    private func focusHeader(in app: XCUIApplication) -> Bool {
        for _ in 0 ..< 6 {
            if headerButton(in: app) != nil {
                return true
            }
            let focused = focusedIdentifier(in: app)
            if focused.hasPrefix("grid.card.") {
                press(.up)
            } else if focused.hasPrefix("grid.letter.") {
                press(.left)
            } else {
                press(.right)
            }
        }
        return headerButton(in: app) != nil
    }

    private func moveAlongHeader(to button: String, in app: XCUIApplication) -> Bool {
        guard let target = buttons.firstIndex(of: button) else { return false }
        for _ in 0 ..< buttons.count {
            guard let current = headerButton(in: app).flatMap(buttons.firstIndex(of:)) else { return false }
            if current == target {
                return true
            }
            press(current < target ? .right : .left)
        }
        return headerButton(in: app) == button
    }
}
