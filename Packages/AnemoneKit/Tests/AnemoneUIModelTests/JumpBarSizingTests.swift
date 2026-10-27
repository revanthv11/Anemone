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

    @Test func `the type keeps its size until the letter gets small`() {
        #expect(sizing.fontSize(letterSize: 32) == 20)
        #expect(sizing.fontSize(letterSize: 28) == 20)
        #expect(sizing.fontSize(letterSize: 24) == 18)
        #expect(sizing.fontSize(letterSize: 16) == 12)
    }
}
