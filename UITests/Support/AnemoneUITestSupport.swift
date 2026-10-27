import XCTest

/// Driving Anemone with the Siri Remote, as the Phase 0 home spike did: elements are found by
/// accessibility identifier (`area.thing`, as in `action.play` or `card.<row>.<item>`), and
/// focus is checked with `hasFocus`.
///
/// Live tests run against the profile the simulator is signed in to. Print `[check] …` lines
/// and attach screenshots, so the test log carries the evidence.
@MainActor
extension XCTestCase {
    /// Launches Anemone afresh, with launch arguments such as `["-libraryGridSpike", "500"]`.
    func launchAnemone(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    /// Waits for Home to show its rows. Fails, with a screenshot, when the simulator isn't
    /// signed in: the tests never sign in themselves.
    @discardableResult
    func waitForHome(_ app: XCUIApplication, timeout: TimeInterval = 30) -> Bool {
        let isCard = NSPredicate(format: "identifier BEGINSWITH 'card.'")
        let card = app.descendants(matching: .any).matching(isCard).firstMatch
        guard card.waitForExistence(timeout: timeout) else {
            attachScreenshot(app, name: "no home")
            XCTFail("Home didn't show its rows. Is the simulator signed in?")
            return false
        }
        return true
    }

    func press(_ button: XCUIRemote.Button, times: Int = 1) {
        for _ in 0 ..< times {
            XCUIRemote.shared.press(button)
        }
    }

    /// Presses each button in turn.
    func press(_ buttons: [XCUIRemote.Button]) {
        buttons.forEach { XCUIRemote.shared.press($0) }
    }

    /// The element with focus; check `exists`, since nothing may have it.
    func focusedElement(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
    }

    /// The focused element's identifier, or "none". In lists, focus is on the row's cell, so a
    /// cell without one of its own reports the first identifier inside it; failing that, the
    /// element's type and label.
    func focusedIdentifier(in app: XCUIApplication) -> String {
        let focused = focusedElement(in: app)
        guard focused.exists else { return "none" }
        guard focused.identifier.isEmpty else { return focused.identifier }
        let inner = focused.descendants(matching: .any).matching(NSPredicate(format: "identifier != ''")).firstMatch
        return inner.exists ? inner.identifier : "\(focused.elementType.rawValue):\(focused.label)"
    }

    /// Whether the element with `identifier`, or the list row holding it, has focus.
    func hasFocus(_ identifier: String, in app: XCUIApplication) -> Bool {
        let element = app.descendants(matching: .any)[identifier]
        if element.exists, element.hasFocus {
            return true
        }
        let cell = app.cells.containing(.any, identifier: identifier).firstMatch
        return cell.exists && cell.hasFocus
    }

    /// Waits until the element with `identifier`, or the list row holding it, has focus.
    @discardableResult
    func waitForFocus(on identifier: String, in app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if hasFocus(identifier, in: app) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return false
    }

    /// The focused element's identifier once it stops changing, for pages whose focus moves on
    /// its own for a moment, like Home's header following focus after 150 ms.
    func settledFocus(in app: XCUIApplication) -> String {
        var previous = focusedIdentifier(in: app)
        for _ in 0 ..< 10 {
            Thread.sleep(forTimeInterval: 0.4)
            let current = focusedIdentifier(in: app)
            if current == previous {
                return current
            }
            previous = current
        }
        return previous
    }

    /// Presses `direction` until the element with `identifier` has focus, at most `limit` times.
    @discardableResult
    func moveFocus(
        to identifier: String,
        pressing direction: XCUIRemote.Button,
        limit: Int = 20,
        in app: XCUIApplication,
    ) -> Bool {
        for _ in 0 ... limit {
            if waitForFocus(on: identifier, in: app, timeout: 0.5) {
                return true
            }
            press(direction)
        }
        return false
    }

    /// Opens a sidebar destination by its title, such as "Settings" or a library's name: moves
    /// left into the sidebar, then down or up to the destination, and selects it.
    @discardableResult
    func openSidebarDestination(_ title: String, in app: XCUIApplication) -> Bool {
        let sidebar = app.collectionViews["Sidebar"]
        let focusedCell = sidebar.cells.matching(NSPredicate(format: "hasFocus == true")).firstMatch
        // Pressing left again from inside the sidebar closes it.
        for _ in 0 ..< 3 where !focusedCell.exists {
            press(.left)
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard focusedCell.exists else { return false }
        let destination = sidebar.cells.containing(NSPredicate(format: "label == %@", title)).firstMatch
        for direction in [XCUIRemote.Button.down, .up] {
            for _ in 0 ..< 15 {
                if destination.exists, destination.hasFocus {
                    press(.select)
                    return true
                }
                press(direction)
                Thread.sleep(forTimeInterval: 0.3)
            }
        }
        return false
    }

    func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
