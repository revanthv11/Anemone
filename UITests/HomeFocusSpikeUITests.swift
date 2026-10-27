import XCTest

/// Phase 0 home-screen spike. Drives the Siri Remote through both prototypes and checks the
/// focus behaviour Anemone's home screen needs. Findings go in docs/spikes/home-focus.md.
///
/// Lines starting with `[spike]` in the test log carry the measurements.
@MainActor
final class HomeFocusSpikeUITests: XCTestCase {
    func testSwiftUIVariant() {
        checkFocusBehaviour(variant: "swiftui")
    }

    func testScrollMemorySwiftUIVariant() {
        checkFocusBehaviour(variant: "swiftui-scroll")
    }

    func testNaiveSwiftUIVariant() {
        checkFocusBehaviour(variant: "swiftui-naive")
    }

    func testUIKitVariant() {
        checkFocusBehaviour(variant: "uikit")
    }

    private func checkFocusBehaviour(variant: String) {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments = ["-homeSpike", variant]
        app.launch()
        let focusedID = app.staticTexts["spike.focusedID"]
        XCTAssertTrue(focusedID.waitForExistence(timeout: 10), "home screen appears")

        XCTAssertEqual(settledFocus(focusedID), "r0-i0", "initial focus")

        let alongRow = timed { press(.right, times: 30) }
        XCTAssertEqual(settledFocus(focusedID), "r0-i30", "moves along row 0")

        // Leave row 1 near its left edge, far from where r0-i30 sits on screen, so plain
        // geometric focus movement would not land back on r0-i30.
        press(.down)
        let firstEntry = settledFocus(focusedID)
        press(.right, times: 3)
        press(.left, times: 6)
        let rowOneItem = settledFocus(focusedID)

        press(.up)
        XCTAssertEqual(settledFocus(focusedID), "r0-i30", "row memory: back up into row 0")
        press(.down)
        XCTAssertEqual(settledFocus(focusedID), rowOneItem, "row memory: back down into row 1")

        let downPage = timed { press(.down, times: 8) }
        XCTAssertTrue(settledFocus(focusedID).hasPrefix("r9-"), "reaches the last row")
        attachScreenshot(app, name: "\(variant) last row")
        press(.up, times: 9)
        let offScreenMemory = settledFocus(focusedID)
        if variant == "swiftui-naive" || variant == "swiftui-scroll" {
            // LazyVStack discards off-screen rows; see docs/spikes/home-focus.md. Strict, so a
            // tvOS release that fixes this makes the test fail and prompts a second look.
            XCTExpectFailure("LazyVStack loses row memory once a row scrolls off screen") {
                XCTAssertEqual(offScreenMemory, "r0-i30", "row memory after row 0 scrolled off screen")
            }
        } else {
            XCTAssertEqual(offScreenMemory, "r0-i30", "row memory after row 0 scrolled off screen")
        }

        // Checked from a fresh position so it doesn't depend on the row-memory result above.
        press(.down, times: 2)
        press(.right, times: 12)
        let beforeDetail = settledFocus(focusedID)
        press(.select)
        XCTAssertTrue(app.staticTexts["detail.title"].waitForExistence(timeout: 5), "opens the detail page")
        press(.menu)
        XCTAssertEqual(settledFocus(focusedID), beforeDetail, "focus restored after going back")
        attachScreenshot(app, name: "\(variant) after back")

        print("[spike] \(variant): first entry into row 1 focused \(firstEntry)")
        print("[spike] \(variant): 30 presses along a row took \(alongRow)")
        print("[spike] \(variant): 8 presses down the page took \(downPage)")
    }

    /// The header updates 150 ms after focus moves, so wait until the reported item stops changing.
    private func settledFocus(_ label: XCUIElement) -> String {
        var previous = label.label
        for _ in 0 ..< 10 {
            Thread.sleep(forTimeInterval: 0.4)
            let current = label.label
            if current == previous {
                return current
            }
            previous = current
        }
        return previous
    }

    private func timed(_ work: () -> Void) -> String {
        let start = Date()
        work()
        return String(format: "%.1f s", Date().timeIntervalSince(start))
    }
}
