import AnemoneUI
import CoreGraphics
import Testing

/// Fitting the alphabet bar into the height beside the grid.
struct JumpBarSizingTests {
    /// As the library grid's bar is set up: 32-point letters, 2 apart, under a 2-point stop.
    private let sizing = JumpBarSizing(
        fullLetterSize: 32,
        minimumLetterSize: 16,
        spacing: 2,
        fixedHeight: 2,
        fullFontSize: 20,
    )
    /// `#` and A to Z.
    private let count = 27
    /// The room beside the grid on Live TV's recordings tab, measured on a 1080p screen.
    private let underTabs: CGFloat = 819
    /// What a library page gives the grid back when it tucks its tabs away, measured in Movies:
    /// the tab row and the padding above it. Fitted to that, the letters grew to 31 points.
    private let tabRow: CGFloat = 78
    /// The room beside a grid under the details header as well (250 points, 16 above the grid).
    private let underDetails: CGFloat = 553

    @Test func `at full size the bar is taller than the room under a page's tabs`() {
        #expect(sizing.height(count: count, letterSize: 32) == 920)
        #expect(sizing.height(count: count, letterSize: 32) > underTabs)
    }

    @Test func `letters shrink to fit the room under a page's tabs`() {
        let size = sizing.letterSize(count: count, fitting: underTabs)

        #expect(size == 28)
        #expect(sizing.height(count: count, letterSize: size) <= underTabs)
    }

    @Test func `letters keep their full size when there's room`() {
        #expect(sizing.letterSize(count: count, fitting: 920) == 32)
        #expect(sizing.letterSize(count: count, fitting: 1080) == 32)
    }

    @Test func `the bar is never taller than its room while the letters can shrink`() {
        let smallest = sizing.height(count: count, letterSize: 16)
        for height in stride(from: smallest, through: 1200, by: 0.5) {
            let size = sizing.letterSize(count: count, fitting: height)
            #expect(sizing.height(count: count, letterSize: size) <= height, "at \(height) points")
        }
    }

    @Test func `letters stop shrinking at the minimum`() {
        #expect(sizing.letterSize(count: count, fitting: 300) == 16)
        #expect(sizing.letterSize(count: count, fitting: 0) == 16)
    }

    @Test func `letters are full size until the height is known`() {
        #expect(sizing.letterSize(count: count, fitting: .infinity) == 32)
        #expect(sizing.letterSize(count: 0, fitting: 500) == 32)
    }

    @Test func `letters keep one size while the tabs tuck away and come back`() {
        // The heights the bar is given as focus moves down past the first row and back, in turn.
        let heights = [underTabs, underTabs + tabRow, underTabs + tabRow, underTabs, underTabs + tabRow, underTabs]
        var least: CGFloat?
        var sizes: [CGFloat] = []
        for height in heights {
            // Drawn with what's known so far, then measured, as JumpBar does.
            sizes.append(sizing.letterSize(count: count, fitting: sizing.roomToFit(now: height, least: least)))
            least = sizing.leastRoom(least, measuring: height)
        }

        #expect(sizes == Array(repeating: 28, count: heights.count))
        // Fitted to the room of the moment, they'd grow while the tabs were away.
        #expect(sizing.letterSize(count: count, fitting: underTabs + tabRow) == 31)
    }

    @Test func `the first frame fits before the bar is measured`() {
        let size = sizing.letterSize(count: count, fitting: sizing.roomToFit(now: underTabs, least: nil))

        #expect(size == 28)
        #expect(sizing.height(count: count, letterSize: size) <= underTabs)
    }

    @Test func `letters shrink at once when the room does`() {
        let least = sizing.leastRoom(underTabs, measuring: underDetails)

        #expect(least == underDetails)
        #expect(sizing.letterSize(count: count, fitting: sizing.roomToFit(now: underDetails, least: underTabs)) == 18)
        #expect(sizing.letterSize(count: count, fitting: sizing.roomToFit(now: underTabs, least: least)) == 18)
    }

    @Test func `a height that isn't real leaves the least room as it was`() {
        #expect(sizing.leastRoom(nil, measuring: 0) == nil)
        #expect(sizing.leastRoom(underTabs, measuring: 0) == underTabs)
        #expect(sizing.leastRoom(underTabs, measuring: .infinity) == underTabs)
        #expect(sizing.leastRoom(nil, measuring: underTabs) == underTabs)
    }

    @Test func `the bar overflows only below the smallest letters' height`() {
        let smallest = sizing.height(count: count, letterSize: 16)

        #expect(smallest == 488)
        #expect(!sizing.overflows(count: count, letterSize: 28, height: underTabs))
        #expect(!sizing.overflows(count: count, letterSize: 28, height: underTabs + tabRow))
        #expect(!sizing.overflows(count: count, letterSize: 16, height: smallest))
        #expect(sizing.overflows(count: count, letterSize: 16, height: smallest - 1))
        for height in stride(from: smallest, through: 1200, by: 0.5) {
            let size = sizing.letterSize(count: count, fitting: height)
            #expect(!sizing.overflows(count: count, letterSize: size, height: height), "at \(height) points")
        }
    }

    @Test func `the type keeps its size until the letter gets small`() {
        #expect(sizing.fontSize(letterSize: 32) == 20)
        #expect(sizing.fontSize(letterSize: 28) == 20)
        #expect(sizing.fontSize(letterSize: 24) == 18)
        #expect(sizing.fontSize(letterSize: 16) == 12)
    }
}
