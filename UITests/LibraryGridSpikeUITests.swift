import XCTest

/// Phase 2b library grid spike. Drives the Siri Remote around the grid on a synthetic library of
/// 5,000 items and checks paging, focus movement, the alphabet bar and focus after Back.
/// Findings go in docs/spikes/home-focus.md.
///
/// XCUITest turns accessibility on, which slows focus in big lazy grids (see the spike doc), so
/// 20,000 items were measured with the profiler instead.
///
/// Lines starting with `[spike]` in the test log carry the measurements.
@MainActor
final class LibraryGridSpikeUITests: XCTestCase {
    private let count = 5000
    private var app: XCUIApplication!

    func testFiveThousandItems() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-libraryGridSpike", "\(count)"]
        app.launch()
        XCTAssertTrue(app.staticTexts["grid.position"].waitForExistence(timeout: 10), "grid appears")

        checkPaging()
        checkAlphabetBar()
        checkDetailAndSidebar()
        checkBackAndHeader()
    }

    /// Straight moves across page boundaries, at the remote's pace.
    private func checkPaging() {
        if !focusedID(app).hasPrefix("grid.card.") {
            print("[spike] \(count): focus at launch was on \(focusedID(app))")
            press(.right)
        }
        XCTAssertEqual(focusedID(app), "grid.card.0", "focus starts on the first card")

        press(.right, times: 5)
        XCTAssertEqual(focusedID(app), "grid.card.5", "moves along the first row")

        // Crosses the first page boundary (100).
        let downTwenty = timed { press(.down, times: 20) }
        XCTAssertEqual(settledFocus(app), "grid.card.125", "moves straight down 20 rows")
        XCTAssertEqual(focusedTitle(app), "E item 125".replacingLetter(index: 125, count: count))

        let downHundred = timed { press(.down, times: 100) }
        XCTAssertEqual(settledFocus(app), "grid.card.725", "moves straight down 100 more rows")
        XCTAssertNotEqual(focusedTitle(app), "placeholder", "the page is there when focus arrives")
        attachScreenshot(app, name: "\(count) after 120 rows")

        print("[spike] \(count): 20 rows down took \(downTwenty)")
        print("[spike] \(count): 100 rows down took \(downHundred)")
        let placeholders = app.staticTexts["spike.placeholderFocusCount"].label
        print("[spike] \(count): focus landed on a loading card \(placeholders) times")
    }

    /// In and out of the alphabet bar from the last column, then a jump to M.
    private func checkAlphabetBar() {
        press(.right)
        let letterOnEntry = focusedID(app)
        XCTAssertTrue(letterOnEntry.hasPrefix("grid.letter."), "right from the last column enters the alphabet bar")
        press(.left)
        XCTAssertEqual(focusedID(app), "grid.card.725", "left from the alphabet bar returns to the same card")

        press(.right)
        let currentLetter = Character(String(letterOnEntry.last ?? "A"))
        let steps = Int(Character("M").asciiValue! - currentLetter.asciiValue!)
        press(.down, times: steps)
        XCTAssertEqual(focusedID(app), "grid.letter.M")
        let jumpStart = Date()
        press(.select)
        let expectedM = (12 * count + 25) / 26
        let landed = waitForFocus(app, on: "grid.card.\(expectedM)", timeout: 5)
        let jumpTime = String(format: "%.1f s", Date().timeIntervalSince(jumpStart))
        XCTAssertTrue(landed, "the M jump focuses the first M item (focus is on \(focusedID(app)))")
        XCTAssertTrue(waitForTitle(app, prefix: "M item"), "the M item has loaded")
        attachScreenshot(app, name: "\(count) after jumping to M")

        print("[spike] \(count): alphabet bar entry focused \(letterOnEntry)")
        print("[spike] \(count): jump to M settled in \(jumpTime)")
    }

    /// A detail page and Back, then the sidebar and back, from deep in the grid.
    private func checkDetailAndSidebar() {
        press(.right)
        let beforeDetail = focusedID(app)
        press(.select)
        XCTAssertTrue(app.staticTexts["detail.title"].waitForExistence(timeout: 5), "opens the detail page")
        press(.menu)
        XCTAssertEqual(settledFocus(app), beforeDetail, "focus returns to the same card after Back")

        press(.left, times: 5)
        let beforeSidebar = settledFocus(app)
        press(.left)
        let inSidebar = focusedID(app)
        XCTAssertFalse(inSidebar.hasPrefix("grid."), "left from the first column reaches the sidebar")
        press(.right)
        XCTAssertEqual(settledFocus(app), beforeSidebar, "right from the sidebar returns to the same card")
        print("[spike] \(count): left into the sidebar focused \(inSidebar)")
    }

    /// Back goes to the top, the header and back, then Back opens the sidebar.
    private func checkBackAndHeader() {
        press(.menu)
        XCTAssertEqual(settledFocus(app), "grid.card.0", "Back returns to the first card")
        press(.up)
        let header = focusedID(app)
        XCTAssertFalse(header.hasPrefix("grid.card."), "up from the first row reaches the header")
        press(.down)
        XCTAssertEqual(focusedID(app), "grid.card.0", "down from the header returns to the grid")
        press(.menu)
        XCTAssertFalse(settledFocus(app).hasPrefix("grid."), "Back from the first card opens the sidebar")
        print("[spike] \(count): up from row 0 focused \(header)")
    }

    // MARK: Helpers

    private func press(_ button: XCUIRemote.Button, times: Int = 1) {
        for _ in 0 ..< times {
            XCUIRemote.shared.press(button)
        }
    }

    private func focusedID(_ app: XCUIApplication) -> String {
        let focused = app.descendants(matching: .any).element(matching: NSPredicate(format: "hasFocus == true"))
        guard focused.exists else { return "none" }
        return focused.identifier.isEmpty ? "\(focused.elementType.rawValue):\(focused.label)" : focused.identifier
    }

    /// Focus can still be moving right after a press or a page transition.
    private func settledFocus(_ app: XCUIApplication) -> String {
        var previous = focusedID(app)
        for _ in 0 ..< 10 {
            Thread.sleep(forTimeInterval: 0.4)
            let current = focusedID(app)
            if current == previous {
                return current
            }
            previous = current
        }
        return previous
    }

    private func waitForFocus(_ app: XCUIApplication, on id: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if focusedID(app) == id {
                return true
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    private func focusedTitle(_ app: XCUIApplication) -> String {
        app.staticTexts["spike.focusedTitle"].label
    }

    private func waitForTitle(_ app: XCUIApplication, prefix: String) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if focusedTitle(app).hasPrefix(prefix) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    private func timed(_ work: () -> Void) -> String {
        let start = Date()
        work()
        return String(format: "%.1f s", Date().timeIntervalSince(start))
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private extension String {
    /// The spike names item `index` of `count` after the letter it's filed under.
    func replacingLetter(index: Int, count: Int) -> String {
        let letter = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")[index * 26 / count]
        return String(letter) + dropFirst()
    }
}
