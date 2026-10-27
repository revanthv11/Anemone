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
    /// size, and no less than the minimum. Full size until the height is known.
    public func letterSize(count: Int, fitting height: CGFloat) -> CGFloat {
        guard count > 0, height.isFinite else { return fullLetterSize }
        let room = (height - fixedHeight) / CGFloat(count) - spacing
        return min(max(room.rounded(.down), minimumLetterSize), fullLetterSize)
    }

    /// How tall the bar stands with `count` letters of `letterSize`.
    public func height(count: Int, letterSize: CGFloat) -> CGFloat {
        fixedHeight + CGFloat(count) * (letterSize + spacing)
    }

    /// The letters' type size: full size while it fills no more than three quarters of the
    /// letter, then shrinking with it.
    public func fontSize(letterSize: CGFloat) -> CGFloat {
        min(fullFontSize, (letterSize * 0.75).rounded(.down))
    }
}
