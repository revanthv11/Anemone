import XCTest

/// A quick live check after a merge: launches, waits for Home, opens the first item in Continue
/// Watching, plays it for about 10 s and closes the player, and checks the item page is back
/// with a resume position.
///
/// Local only. It needs a simulator signed in to a server, and it moves the item's resume
/// position, so it's skipped unless the test runner has `ANEMONE_LIVE_SMOKE=1`. xcodebuild
/// passes variables starting with `TEST_RUNNER_` on to the test runner without that prefix:
///
///     TEST_RUNNER_ANEMONE_LIVE_SMOKE=1 xcodebuild test -project Anemone.xcodeproj -scheme Anemone \
///         -destination "id=<simulator>" -only-testing:AnemoneUITests/SmokeUITests
///
/// `test-without-building` after a `build-for-testing` works the same way. To play a particular
/// Continue Watching item rather than the first, add `TEST_RUNNER_ANEMONE_SMOKE_ITEM=<item ID>`.
@MainActor
final class SmokeUITests: XCTestCase {
    private let environment = ProcessInfo.processInfo.environment

    override func setUpWithError() throws {
        try XCTSkipUnless(environment["ANEMONE_LIVE_SMOKE"] == "1", "Set ANEMONE_LIVE_SMOKE=1 to play live")
        continueAfterFailure = false
    }

    func testPlayFromContinueWatching() {
        let app = launchAnemone()
        guard waitForHome(app) else { return }

        let isContinueWatching = NSPredicate(format: "identifier BEGINSWITH 'card.continueWatching.'")
        let firstCard = app.descendants(matching: .any).matching(isContinueWatching).firstMatch
        XCTAssertTrue(firstCard.exists, "Home has a Continue Watching row")
        let card = environment["ANEMONE_SMOKE_ITEM"].map { "card.continueWatching.\($0)" } ?? firstCard.identifier
        XCTAssertTrue(moveFocus(to: card, pressing: .right, in: app), "\(card) takes focus on Home")
        press(.select)

        // The page opens with focus on Resume.
        let resume = app.buttons["action.resume"]
        XCTAssertTrue(waitForFocus(on: "action.resume", in: app, timeout: 15), "the item page offers Resume")
        let before = resume.label
        press(.select)
        Thread.sleep(forTimeInterval: 10)
        attachScreenshot(app, name: "playing")
        XCTAssertFalse(app.descendants(matching: .any)["player.failure"].exists, "plays without an error")

        // Checked by focus: the page's buttons stay in the tree behind the player.
        press(.menu)
        // When the first Menu only hid the player's controls, the second closes it.
        if !waitForFocus(on: "action.resume", in: app, timeout: 5) {
            press(.menu)
        }
        XCTAssertTrue(waitForFocus(on: "action.resume", in: app, timeout: 15), "closing the player goes back")
        // The page reloads once the server has the new position.
        let moved = NSPredicate { _, _ in resume.label != before }
        _ = XCTWaiter.wait(for: [expectation(for: moved, evaluatedWith: nil)], timeout: 10)
        attachScreenshot(app, name: "after playing")
        print("[check] \(card): \(before) before playing, \(resume.label) after")
    }
}
