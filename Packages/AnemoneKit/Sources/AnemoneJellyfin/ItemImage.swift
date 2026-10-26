import Foundation

/// One image on the server: whose it is, which kind, and its tag.
public struct ItemImage: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case primary = "Primary"
        case thumb = "Thumb"
        case backdrop = "Backdrop"
        case logo = "Logo"
    }

    public let itemID: String
    public let kind: Kind
    public let tag: String

    public init(itemID: String, kind: Kind, tag: String) {
        self.itemID = itemID
        self.kind = kind
        self.tag = tag
    }

    /// `nil` unless both the item and the tag are known; a missing tag means there's no image.
    init?(itemID: String?, kind: Kind, tag: String?) {
        guard let itemID, let tag else { return nil }
        self.init(itemID: itemID, kind: kind, tag: tag)
    }
}

/// Which image a card or backdrop shows, ported from Wholphin's `ImageUrlService`.
public extension MediaItem {
    /// 2:3 art. Episodes use their series' poster, and seasons without their own fall back to it.
    var posterImage: ItemImage? {
        switch kind {
        case .episode:
            artwork.seriesPrimary ?? own(.primary)
        case .season:
            own(.primary) ?? artwork.seriesPrimary
        default:
            own(.primary)
        }
    }

    /// 16:9 art: the item's own thumb; for episodes and seasons, the series thumb, then the
    /// series backdrop; then the item's backdrop, then its primary image (an episode's still).
    var thumbImage: ItemImage? {
        if let thumb = own(.thumb) {
            return thumb
        }
        if isPartOfSeries, let parent = artwork.parentThumb ?? artwork.parentBackdrop {
            return parent
        }
        return own(.backdrop) ?? own(.primary)
    }

    /// 1:1 art, such as album covers.
    var squareImage: ItemImage? {
        own(.primary)
    }

    /// Full-screen art behind the home header. Episodes and seasons use the series backdrop.
    var backdropImage: ItemImage? {
        if isPartOfSeries, let parent = artwork.parentBackdrop {
            return parent
        }
        return own(.backdrop)
    }

    private var isPartOfSeries: Bool {
        kind == .episode || kind == .season
    }

    private func own(_ kind: ItemImage.Kind) -> ItemImage? {
        let tag: String? = switch kind {
        case .primary: artwork.primaryTag
        case .thumb: artwork.thumbTag
        case .backdrop: artwork.backdropTag
        // Cards don't carry logos; item pages get them from `ItemDetails`.
        case .logo: nil
        }
        return ItemImage(itemID: id, kind: kind, tag: tag)
    }
}
