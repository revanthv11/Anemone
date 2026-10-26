import UIKit

// Phase 0 spike: mock home-screen content shared by the SwiftUI and UIKit variants.

struct SpikeItem: Identifiable, Hashable {
    /// `r<row>-i<index>`. Also the accessibility identifier the UI tests look for.
    let id: String
    let rowID: SpikeRow.ID
    let title: String
    let hue: Double
}

struct SpikeRow: Identifiable, Hashable {
    let id: String
    let title: String
    let items: [SpikeItem]
}

nonisolated enum SpikeLayout {
    static let posterSize = CGSize(width: 200, height: 300)
    static let posterSpacing: CGFloat = 40
    static let rowSpacing: CGFloat = 24
    /// Room above and below each row so the focus lift isn't clipped.
    static let focusPadding: CGFloat = 30
    static let horizontalInset: CGFloat = 80
}

enum SpikeData {
    static let rows: [SpikeRow] = rowTitles.enumerated().map { rowIndex, title in
        let rowID = "r\(rowIndex)"
        let items = (0 ..< 50).map { index in
            SpikeItem(
                id: "\(rowID)-i\(index)",
                rowID: rowID,
                title: "\(title) \(index + 1)",
                hue: Double((rowIndex * 50 + index) % 97) / 97,
            )
        }
        return SpikeRow(id: rowID, title: title, items: items)
    }

    static func item(id: SpikeItem.ID) -> SpikeItem? {
        itemsByID[id]
    }

    static func row(id: SpikeRow.ID) -> SpikeRow? {
        rows.first { $0.id == id }
    }

    private static let itemsByID = Dictionary(
        uniqueKeysWithValues: rows.flatMap(\.items).map { ($0.id, $0) },
    )

    private static let rowTitles = [
        "Continue Watching", "Next Up", "Recently Added Movies", "Recently Added Shows", "Favorites",
        "Action", "Comedy", "Drama", "Documentaries", "Collections",
    ]
}

/// Stand-in for network posters. Draws each poster off the main thread so scrolling pays a
/// realistic per-card cost instead of rendering flat colours.
final class PosterImageCache {
    static let shared = PosterImageCache()

    private let cache = NSCache<NSString, UIImage>()

    func cachedImage(for item: SpikeItem) -> UIImage? {
        cache.object(forKey: item.id as NSString)
    }

    func image(for item: SpikeItem) async -> UIImage {
        if let cached = cachedImage(for: item) {
            return cached
        }
        let image = await Self.render(title: item.title, hue: item.hue)
        cache.setObject(image, forKey: item.id as NSString)
        return image
    }

    /// Core Graphics and Core Text only: UIKit's image renderer is main-actor-bound.
    @concurrent
    private static func render(title: String, hue: Double) async -> UIImage {
        let width = Int(SpikeLayout.posterSize.width * 2)
        let height = Int(SpikeLayout.posterSize.height * 2)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else { return UIImage() }

        let colors = [
            UIColor(hue: hue, saturation: 0.6, brightness: 0.85, alpha: 1).cgColor,
            UIColor(hue: hue, saturation: 0.8, brightness: 0.25, alpha: 1).cgColor,
        ]
        if let gradient = CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: nil) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: height),
                end: .zero,
                options: [],
            )
        }

        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, 40, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: title,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font as Any,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): UIColor.white.cgColor,
            ],
        ))
        context.textPosition = CGPoint(x: 24, y: 40)
        CTLineDraw(line, context)

        guard let image = context.makeImage() else { return UIImage() }
        return UIImage(cgImage: image)
    }
}
