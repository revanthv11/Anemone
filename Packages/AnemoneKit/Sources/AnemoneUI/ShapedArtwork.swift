import SwiftUI

/// Artwork in a fixed frame of a card shape, over a placeholder in the theme's colours that shows
/// until (or unless) the image arrives.
public struct ShapedArtwork: View {
    private let url: URL?
    private let shape: CardShape
    private let width: CGFloat
    private let cornerRadius: CGFloat
    private let placeholderOverride: String?

    @Environment(\.theme) private var theme

    /// - Parameter placeholderSymbol: an SF Symbol to show until the image arrives, in place of
    ///   the shape's usual one.
    public init(
        url: URL?,
        shape: CardShape,
        width: CGFloat,
        cornerRadius: CGFloat = 12,
        placeholderSymbol: String? = nil,
    ) {
        self.url = url
        self.shape = shape
        self.width = width
        self.cornerRadius = cornerRadius
        placeholderOverride = placeholderSymbol
    }

    public var body: some View {
        ZStack {
            Rectangle()
                .fill(theme.surfaceVariant)
            Image(systemName: placeholderOverride ?? placeholderSymbol)
                .font(.system(size: 48))
                .foregroundStyle(theme.onSurfaceVariant)
            ArtworkImage(url: url)
        }
        .frame(width: width, height: width / shape.aspectRatio)
        .clipShape(.rect(cornerRadius: cornerRadius))
        // Decoration: the card or page around it names what it shows, and the placeholder's
        // symbol would otherwise be read by its own name.
        .accessibilityHidden(true)
    }

    private var placeholderSymbol: String {
        switch shape {
        case .poster: "film"
        case .thumb: "tv"
        case .square: "music.note"
        }
    }
}
