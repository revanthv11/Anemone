import SwiftUI

/// A poster, thumb or square card with a caption, for rows and grids.
///
/// Put it in a borderless button: on tvOS the artwork lifts when focused, like the TV app.
public struct MediaCard: View {
    private let title: String
    private let subtitle: String?
    private let imageURL: URL?
    private let shape: CardShape
    private let width: CGFloat
    private let progress: Double?

    /// - Parameter progress: from 0 to 1; draws a bar along the bottom when above 0.
    public init(
        title: String,
        subtitle: String? = nil,
        imageURL: URL?,
        shape: CardShape,
        width: CGFloat,
        progress: Double? = nil,
    ) {
        self.title = title
        self.subtitle = subtitle
        self.imageURL = imageURL
        self.shape = shape
        self.width = width
        self.progress = progress
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            artwork
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                Text(subtitle ?? " ")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: width, alignment: .leading)
        }
    }

    private var artwork: some View {
        ZStack {
            Rectangle()
                .fill(.quaternary)
            Image(systemName: placeholderSymbol)
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            ArtworkImage(url: imageURL)
        }
        .frame(width: width, height: width / shape.aspectRatio)
        .overlay(alignment: .bottom) {
            if let progress, progress > 0 {
                ProgressBar(progress: progress, width: width - 2 * Self.progressInset)
                    .padding(.bottom, Self.progressInset)
            }
        }
        .clipShape(.rect(cornerRadius: 12))
        #if os(tvOS)
            .hoverEffect(.highlight)
        #endif
    }

    private var placeholderSymbol: String {
        switch shape {
        case .poster: "film"
        case .thumb: "tv"
        case .square: "music.note"
        }
    }

    private static let progressInset: CGFloat = 12
}

private struct ProgressBar: View {
    let progress: Double
    let width: CGFloat

    var body: some View {
        Capsule()
            .fill(.black.opacity(0.5))
            .frame(width: width, height: 8)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(.white)
                    .frame(width: width * min(progress, 1))
            }
            .accessibilityElement()
            .accessibilityLabel("\(Int((progress * 100).rounded()))% watched")
    }
}
