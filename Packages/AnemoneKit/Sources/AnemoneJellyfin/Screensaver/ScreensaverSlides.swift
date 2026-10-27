import Foundation
import JellyfinAPI

/// One picture of the in-app screensaver: an item's backdrop, with its logo, or its title when
/// it has none. Ported from Wholphin's `ScreensaverItem.CurrentItem`.
public struct ScreensaverSlide: Hashable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let backdrop: ItemImage
    public let logo: ItemImage?

    public init(id: String, title: String, backdrop: ItemImage, logo: ItemImage? = nil) {
        self.id = id
        self.title = title
        self.backdrop = backdrop
        self.logo = logo
    }
}

public extension JellyfinSession {
    /// What the screensaver shows, as Wholphin's `ScreensaverService.createPager` asks for it:
    /// movies and series that have a backdrop, in random order, rated for at most
    /// `maxAgeRating` years (`nil` for any rating). Wholphin pages through every match; the
    /// screensaver asks again for a new random set once it has shown these.
    func screensaverSlides(maxAgeRating: Int?, limit: Int = 100) async throws -> [ScreensaverSlide] {
        var parameters = Paths.GetItemsParameters(userID: userID)
        parameters.isRecursive = true
        parameters.includeItemTypes = [.movie, .series]
        parameters.imageTypes = [.backdrop]
        parameters.sortBy = [.random]
        parameters.limit = limit
        // As in Wholphin: the server reads a bare number as an age, and items without a rating
        // are left out once there's a limit.
        if let maxAgeRating {
            parameters.maxOfficialRating = String(maxAgeRating)
            parameters.hasParentalRating = true
        }
        parameters.enableImageTypes = [.backdrop, .logo]
        parameters.imageTypeLimit = 1
        parameters.enableTotalRecordCount = false
        let items = try await send(Paths.getItems(parameters: parameters)).items ?? []
        return items.compactMap(ScreensaverSlide.init)
    }
}

private extension ScreensaverSlide {
    init?(_ dto: BaseItemDto) {
        guard let id = dto.id, let backdrop = ItemImage(itemID: id, kind: .backdrop, tag: dto.backdropImageTags?.first)
        else { return nil }
        self.init(
            id: id,
            title: dto.name ?? "",
            backdrop: backdrop,
            logo: ItemImage(itemID: id, kind: .logo, tag: dto.imageTags?[ImageType.logo.rawValue]),
        )
    }
}
