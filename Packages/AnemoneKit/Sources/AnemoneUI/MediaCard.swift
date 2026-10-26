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
    private let showsCaption: Bool

    /// - Parameters:
    ///   - progress: from 0 to 1; draws a bar along the bottom when above 0.
    ///   - showsCaption: whether the title and subtitle show under the artwork.
    public init(
        title: String,
        subtitle: String? = nil,
        imageURL: URL?,
        shape: CardShape,
        width: CGFloat,
        progress: Double? = nil,
        showsCaption: Bool = true,
    ) {
        self.title = title
        self.subtitle = subtitle
        self.imageURL = imageURL
        self.shape = shape
        self.width = width
        self.progress = progress
        self.showsCaption = showsCaption
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            artwork
            if showsCaption {
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
    }

    private var artwork: some View {
        ShapedArtwork(url: imageURL, shape: shape, width: width)
            .overlay(alignment: .bottom) {
                if let progress, progress > 0 {
                    ProgressBar(progress: progress, width: width - 2 * Self.progressInset)
                        .padding(.bottom, Self.progressInset)
                }
            }
            .liftOnFocus()
    }

    private static let progressInset: CGFloat = 12
}

private extension View {
    /// The TV app's focus lift; tvOS only.
    @ViewBuilder
    func liftOnFocus() -> some View {
        #if os(tvOS)
            hoverEffect(.highlight)
        #else
            self
        #endif
    }
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
