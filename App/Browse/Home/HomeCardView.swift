import AnemoneCore
import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// A card on a home row, drawn as its row's view options say, like Wholphin's
/// `HomePageCardContent`: genres and studios as art with their name over it, everything else as
/// a media card.
struct HomeCardView: View {
    let card: HomeCard
    let options: HomeRowViewOptions
    /// Whether the card's long-press menu is offered.
    var hasMenu = true

    @Environment(BrowseModel.self) private var browse
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let style = HomeCardStyle(card: card, options: options)
        let imageURL = browse.imageURL(style.image, width: style.width * displayScale)
        switch card.destination {
        case .items:
            HomeCategoryCard(name: card.item.name, imageURL: imageURL, shape: style.shape, width: style.width)
        case .item:
            MediaCard(
                title: card.item.displayTitle,
                subtitle: card.item.subtitle ?? card.item.year.map(String.init),
                imageURL: imageURL,
                shape: style.shape,
                width: style.width,
                progress: card.item.progress,
                showsCaption: options.showTitles,
                // A home row holds no watched or favourite state, so the menu offers both ways.
                menuItem: hasMenu ? CardMenuItem(card.item) : nil,
            )
        }
    }
}

/// How big a card is and which image it shows, from Wholphin's view options. Episodes have
/// their own image settings.
struct HomeCardStyle {
    /// Wholphin's sizes are Android dp on a screen 960 dp wide; this keeps its default poster
    /// at the 200 × 300 points Anemone's rows have used.
    static let pointsPerDp: CGFloat = 1.75
    /// Wholphin's 16 dp default gap becomes the 40 points Anemone's rows have used, leaving room
    /// for the focus lift.
    static let spacingPointsPerDp: CGFloat = 2.5

    let shape: CardShape
    let width: CGFloat
    let image: ItemImage?

    init(card: HomeCard, options: HomeRowViewOptions) {
        let item = card.item
        let isEpisode = item.kind == .episode
        let aspectRatio = isEpisode ? options.episodeAspectRatio : options.aspectRatio
        let imageType = isEpisode ? options.episodeImageType : options.imageType
        shape = Self.shape(for: aspectRatio)
        width = (CGFloat(options.heightDp) * Self.pointsPerDp * shape.aspectRatio).rounded()
        image = card.image ?? Self.image(of: item, type: imageType, shape: shape, useSeries: options.useSeries)
    }

    /// Anemone's cards come in three shapes, so 4:3 is drawn 16:9.
    static func shape(for ratio: HomeRowViewOptions.AspectRatio) -> CardShape {
        switch ratio {
        case .tall: .poster
        case .wide, .fourThree: .thumb
        case .square: .square
        }
    }

    private static func image(
        of item: MediaItem,
        type: HomeRowViewOptions.ImageType,
        shape: CardShape,
        useSeries: Bool,
    ) -> ItemImage? {
        // An episode shows its own still unless the row uses series art.
        if item.kind == .episode, !useSeries {
            let still = item.artwork.primaryTag.map { ItemImage(itemID: item.id, kind: .primary, tag: $0) }
            guard type == .thumb, let thumb = item.artwork.thumbTag else { return still }
            return ItemImage(itemID: item.id, kind: .thumb, tag: thumb)
        }
        switch type {
        case .thumb: return item.thumbImage
        case .primary: return shape == .square ? item.squareImage : item.posterImage
        }
    }
}

/// Wholphin's `GenreCard` and `StudioCard`: art with the name over it.
private struct HomeCategoryCard: View {
    let name: String
    let imageURL: URL?
    let shape: CardShape
    let width: CGFloat

    var body: some View {
        ShapedArtwork(url: imageURL, shape: shape, width: width, placeholderSymbol: "square.stack")
            .overlay {
                LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                    .clipShape(.rect(cornerRadius: 12))
            }
            .overlay {
                Text(name)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(16)
            }
            .hoverEffect(.highlight)
            .accessibilityElement(children: .combine)
    }
}

extension CardShape {
    var cardWidth: CGFloat {
        switch self {
        case .poster: 200
        case .thumb: 340
        case .square: 240
        }
    }
}

extension MediaItem {
    func image(for shape: CardShape) -> ItemImage? {
        switch shape {
        case .poster: posterImage
        case .thumb: thumbImage
        case .square: squareImage
        }
    }

    /// The episode ("S1:E3 · Pilot") or season shown under the series name.
    var subtitle: String? {
        switch kind {
        case .episode:
            [episodeLabel, name].compactMap(\.self).joined(separator: " · ")
        case .season:
            name
        default:
            nil
        }
    }

    /// Year, running time and age rating, such as "2024 · 1h 52m · PG-13".
    var details: String {
        [
            year.map(String.init),
            runtime.map { $0.formatted(.units(allowed: [.hours, .minutes], width: .narrow)) },
            officialRating,
        ]
        .compactMap(\.self)
        .joined(separator: " · ")
    }
}
