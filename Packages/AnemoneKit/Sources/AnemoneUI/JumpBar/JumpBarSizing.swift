import CoreGraphics

/// Fits the library grid's alphabet bar into the height beside the grid.
///
/// At full size, `#` to `Z` stand 920 points tall, which is more than a grid under a page's tabs
/// gets (about 820 points). The bar is a plain column that can't scroll or squeeze, so it made the
/// page taller than the screen, and tvOS centred the page: Live TV's tabs went up under the
/// sidebar's title, and the movie and show grids lost their last letters and the position
/// footer off the bottom. So the letters keep their size while they fit, and shrink evenly
/// when they don't.
public struct JumpBarSizing: Equatable, Sendable {
    /// A letter's size when there's room.
    public var fullLetterSize: CGFloat
    /// The least a letter shrinks to; below it the bar would be too small to read.
    public var minimumLetterSize: CGFloat
    /// Between one row of the bar and the next.
    public var spacing: CGFloat
    /// The rows above the letters that keep their height, such as the bar's stop above `#`.
    public var fixedHeight: CGFloat
    /// The letters' type size at full size.
    public var fullFontSize: CGFloat

    public init(
        fullLetterSize: CGFloat,
        minimumLetterSize: CGFloat,
        spacing: CGFloat,
        fixedHeight: CGFloat,
        fullFontSize: CGFloat,
    ) {
        self.fullLetterSize = fullLetterSize
        self.minimumLetterSize = minimumLetterSize
        self.spacing = spacing
        self.fixedHeight = fixedHeight
        self.fullFontSize = fullFontSize
    }

    /// The size, in whole points, at which `count` letters fit in `height`: no more than full
    /// size, and no less than the minimum. Full size for an unknown (infinite) height.
    public func letterSize(count: Int, fitting height: CGFloat) -> CGFloat {
        guard count > 0, height.isFinite else { return fullLetterSize }
        let room = (height - fixedHeight) / CGFloat(count) - spacing
        return min(max(room.rounded(.down), minimumLetterSize), fullLetterSize)
    }

    /// How tall the bar stands with `count` letters of `letterSize`.
    public func height(count: Int, letterSize: CGFloat) -> CGFloat {
        fixedHeight + CGFloat(count) * (letterSize + spacing)
    }

    /// The least room the bar has had since it appeared, now that `height` has been measured;
    /// `nil` until a height is known.
    ///
    /// The letters are fitted to this rather than to the room of the moment, so they keep one
    /// size while the grid scrolls: a library page tucks its tabs away while focus is past the
    /// grid's first row, giving the bar the tab row's height for a while, and letters fitted to
    /// that grew a few points, then shrank again as the tabs came back. A bar appears with the
    /// tabs showing, so this is the room under them. The room never grows for good on a TV's
    /// screen; turning the details header on or off builds a new bar.
    public func leastRoom(_ least: CGFloat?, measuring height: CGFloat) -> CGFloat? {
        guard height > 0, height.isFinite else { return least }
        return min(least ?? height, height)
    }

    /// The height to fit the letters in: the room the bar has now, or the least it has had
    /// (`leastRoom`) when that's less. The room it has now until that's been measured, so the
    /// bar fits from the first frame it draws.
    public func roomToFit(now height: CGFloat, least: CGFloat?) -> CGFloat {
        min(height, least ?? height)
    }

    /// Whether `count` letters of `letterSize` stand taller than `height`, as they do in a room
    /// too small for even the smallest letters.
    public func overflows(count: Int, letterSize: CGFloat, height: CGFloat) -> Bool {
        self.height(count: count, letterSize: letterSize) > height
    }

    /// The letters' type size: full size while it fills no more than three quarters of the
    /// letter, then shrinking with it.
    public func fontSize(letterSize: CGFloat) -> CGFloat {
        min(fullFontSize, (letterSize * 0.75).rounded(.down))
    }
}
