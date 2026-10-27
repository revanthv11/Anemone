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
    private let badges: CardBadges
    private let showsCaption: Bool
    private let menuItem: CardMenuItem?

    @Environment(\.cardMenu) private var menu

    /// - Parameters:
    ///   - progress: from 0 to 1; draws a bar along the bottom when above 0.
    ///   - showsCaption: whether the title and subtitle show under the artwork.
    ///   - menuItem: what the card shows, for the long-press menu that `cardMenu()` on the
    ///     card's button opens; no menu when `nil`.
    public init(
        title: String,
        subtitle: String? = nil,
        imageURL: URL?,
        shape: CardShape,
        width: CGFloat,
        progress: Double? = nil,
        badges: CardBadges = CardBadges(),
        showsCaption: Bool = true,
        menuItem: CardMenuItem? = nil,
    ) {
        self.title = title
        self.subtitle = subtitle
        self.imageURL = imageURL
        self.shape = shape
        self.width = width
        self.progress = progress
        self.badges = badges
        self.showsCaption = showsCaption
        self.menuItem = menuItem
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            artwork(shownMarks)
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
        .preference(key: CardMenuRequestKey.self, value: menuItem.map { CardMenuRequest(item: $0, marks: givenMarks) })
    }

    private var givenMarks: CardMarks {
        CardMarks(badges: badges, progress: progress)
    }

    /// The caller's marks, or what a card menu changed them to since.
    private var shownMarks: CardMarks {
        guard let menuItem, let menu else { return givenMarks }
        return menu.marks.marks(for: menuItem.id, given: givenMarks)
    }

    private func artwork(_ marks: CardMarks) -> some View {
        let badges = marks.badges
        let progress = marks.progress
        return ShapedArtwork(url: imageURL, shape: shape, width: width)
            .overlay(alignment: .bottom) {
                if let progress, progress > 0 {
                    ProgressBar(progress: progress, width: width - 2 * Self.progressInset)
                        .padding(.bottom, Self.progressInset)
                }
            }
            .overlay(alignment: .topLeading) {
                if badges.isFavorite {
                    Badge(systemImage: "heart.fill", tint: .red, label: "Favorite")
                        .padding(Self.progressInset)
                }
            }
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 8) {
                    // Partly watched items have the progress bar instead, as in Wholphin.
                    if badges.isPlayed, (progress ?? 0) <= 0 {
                        Badge(systemImage: "checkmark", tint: .white, label: "Watched")
                    }
                    if let count = badges.unplayedCount, count > 0 {
                        Text(count, format: .number.notation(.compactName))
                            .font(.caption2.bold())
                            .padding(.horizontal, 12)
                            .frame(minWidth: Badge.size, minHeight: Badge.size)
                            .foregroundStyle(.white)
                            .background(.black.opacity(0.6), in: .capsule)
                            .accessibilityLabel("\(count) unwatched")
                    }
                }
                .padding(Self.progressInset)
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

/// Marks drawn over a card's artwork, like Wholphin's card overlay: a heart for favourites, and a
/// check or an unwatched count in the corner.
public struct CardBadges: Hashable, Sendable {
    public var isFavorite: Bool
    public var isPlayed: Bool
    /// For series, seasons and collections.
    public var unplayedCount: Int?

    public init(isFavorite: Bool = false, isPlayed: Bool = false, unplayedCount: Int? = nil) {
        self.isFavorite = isFavorite
        self.isPlayed = isPlayed
        self.unplayedCount = unplayedCount
    }
}

private struct Badge: View {
    static let size: CGFloat = 44

    let systemImage: String
    let tint: Color
    let label: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.caption2.bold())
            .foregroundStyle(tint)
            .frame(width: Self.size, height: Self.size)
            .background(.black.opacity(0.6), in: .circle)
            .accessibilityLabel(label)
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
