import SwiftUI

/// Artwork in a fixed frame of a card shape, over a placeholder that shows until (or unless) the
/// image arrives.
public struct ShapedArtwork: View {
    private let url: URL?
    private let shape: CardShape
    private let width: CGFloat
    private let cornerRadius: CGFloat

    public init(url: URL?, shape: CardShape, width: CGFloat, cornerRadius: CGFloat = 12) {
        self.url = url
        self.shape = shape
        self.width = width
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        ZStack {
            Rectangle()
                .fill(.quaternary)
            Image(systemName: placeholderSymbol)
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            ArtworkImage(url: url)
        }
        .frame(width: width, height: width / shape.aspectRatio)
        .clipShape(.rect(cornerRadius: cornerRadius))
    }

    private var placeholderSymbol: String {
        switch shape {
        case .poster: "film"
        case .thumb: "tv"
        case .square: "music.note"
        }
    }
}
