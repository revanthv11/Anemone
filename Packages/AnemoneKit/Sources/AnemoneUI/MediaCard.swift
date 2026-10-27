import SwiftUI

/// A poster, thumb or square card with a caption, for rows and grids.
///
/// Put it in a borderless button: on tvOS the artwork lifts when focused, like the TV app, with a
/// ring in the theme's focus colour, as Wholphin's cards have.
///
/// VoiceOver reads it as one element, whether or not the caption shows: the title, the subtitle,
/// then the marks over the artwork (`CardSpokenMark`). The artwork itself is decoration.
public struct MediaCard: View {
    private let title: String
    private let subtitle: String?
    private let spokenSubtitle: Text?
    private let imageURL: URL?
    private let shape: CardShape
    private let width: CGFloat
    private let progress: Double?
    private let badges: CardBadges
    private let showsCaption: Bool
    private let menuItem: CardMenuItem?

    @Environment(\.cardMenu) private var menu
    @Environment(\.theme) private var theme
    @Environment(\.isFocused) private var isFocused

    /// - Parameters:
    ///   - spokenSubtitle: what VoiceOver reads for the subtitle when it's written for the eye,
    ///     like an episode's "S1:E3"; the subtitle itself when `nil`.
    ///   - progress: from 0 to 1; draws a bar along the bottom when above 0.
    ///   - showsCaption: whether the title and subtitle show under the artwork.
    ///   - menuItem: what the card shows, for the long-press menu that `cardMenu()` on the
    ///     card's button opens; no menu when `nil`.
    public init(
        title: String,
        subtitle: String? = nil,
        spokenSubtitle: Text? = nil,
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
        self.spokenSubtitle = spokenSubtitle
        self.imageURL = imageURL
        self.shape = shape
        self.width = width
        self.progress = progress
        self.badges = badges
        self.showsCaption = showsCaption
        self.menuItem = menuItem
    }

    public var body: some View {
        let marks = shownMarks
        VStack(alignment: .leading, spacing: 12) {
            artwork(marks)
            if showsCaption {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(theme.onBackground)
                        .lineLimit(1)
                    Text(subtitle ?? " ")
                        .font(.caption2)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }
                .frame(width: width, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel { _ in
            Text(verbatim: title)
            if let subtitle = spokenSubtitle ?? writtenSubtitle {
                subtitle
            }
            ForEach(CardSpokenMark.marks(for: marks), id: \.self) { mark in
                Text(mark.spoken)
            }
        }
        .preference(key: CardMenuRequestKey.self, value: menuItem.map { CardMenuRequest(item: $0, marks: givenMarks) })
    }

    /// The subtitle as written, unless there's nothing to read.
    private var writtenSubtitle: Text? {
        guard let subtitle, !subtitle.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return Text(verbatim: subtitle)
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
        return ShapedArtwork(url: imageURL, shape: shape, width: width, cornerRadius: Self.cornerRadius)
            .overlay(alignment: .bottom) {
                if let progress, progress > 0 {
                    ProgressBar(progress: progress, width: width - 2 * Self.progressInset)
                        .padding(.bottom, Self.progressInset)
                }
            }
            .overlay(alignment: .topLeading) {
                if badges.isFavorite {
                    Badge(systemImage: "heart.fill", tint: theme.favorite, fill: theme.cardBadge)
                        .padding(Self.progressInset)
                }
            }
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 8) {
                    // Partly watched items have the progress bar instead, as in Wholphin.
                    if badges.isPlayed, (progress ?? 0) <= 0 {
                        Badge(
                            systemImage: "checkmark",
                            tint: theme.onWatchedBadge,
                            fill: theme.watchedBadge,
                        )
                    }
                    if let count = badges.unplayedCount, count > 0 {
                        Text(count, format: .number.notation(.compactName))
                            .font(.caption2.bold())
                            .padding(.horizontal, 12)
                            .frame(minWidth: Badge.size, minHeight: Badge.size)
                            .foregroundStyle(theme.onCardBadge)
                            .background(theme.cardBadge, in: .capsule)
                    }
                }
                .padding(Self.progressInset)
            }
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: Self.cornerRadius)
                        .strokeBorder(theme.focusRing, lineWidth: Theme.focusRingWidth)
                }
            }
            .liftOnFocus()
    }

    private static let progressInset: CGFloat = 12
    private static let cornerRadius: CGFloat = 12
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
    let tint: ThemeColor
    let fill: ThemeColor

    var body: some View {
        Image(systemName: systemImage)
            .font(.caption2.bold())
            .foregroundStyle(tint)
            .frame(width: Self.size, height: Self.size)
            .background(fill, in: .circle)
    }
}

/// How much has been watched, in the theme's progress colours.
private struct ProgressBar: View {
    let progress: Double
    let width: CGFloat

    @Environment(\.theme) private var theme

    var body: some View {
        Capsule()
            .fill(theme.progressTrack)
            .frame(width: width, height: 8)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(theme.progress)
                    .frame(width: width * min(progress, 1))
            }
    }
}
