import AnemoneCore
import Foundation
import JellyfinAPI

/// One picture of the in-app screensaver: an item's backdrop, with its logo, or its title when
/// it has none; for a photo, the photo itself with the date it was taken. Ported from Wholphin's
/// `ScreensaverItem.CurrentItem`.
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

/// Which types of item the screensaver shows, Wholphin's "Include types" (`ScreensaverPreference
/// .ItemTypes`): movies and shows by default, and photos, which show as themselves. Stored as
/// the server's names joined with commas, such as "Movie,Series".
public struct ScreensaverItemTypes: Hashable, Sendable, RawRepresentable, PreferenceValue {
    /// In Wholphin's order.
    public enum Kind: String, CaseIterable, Sendable {
        case movie = "Movie"
        case series = "Series"
        case photo = "Photo"
    }

    public var kinds: Set<Kind>

    public init(_ kinds: Set<Kind>) {
        self.kinds = kinds
    }

    /// Wholphin's default.
    public static let `default` = Self([.movie, .series])

    public init?(rawValue: String) {
        // Names it doesn't know, from an older or newer build, are left out.
        kinds = Set(rawValue.split(separator: ",")
            .compactMap { Kind(rawValue: $0.trimmingCharacters(in: .whitespaces)) })
    }

    public var rawValue: String {
        Kind.allCases.filter(kinds.contains).map(\.rawValue).joined(separator: ",")
    }

    /// Whether `kind` is shown.
    public func contains(_ kind: Kind) -> Bool {
        kinds.contains(kind)
    }

    /// Shows `kind` or stops showing it.
    public mutating func set(_ kind: Kind, included: Bool) {
        if included {
            kinds.insert(kind)
        } else {
            kinds.remove(kind)
        }
    }
}

public extension JellyfinSession {
    /// What the screensaver shows, as Wholphin's `ScreensaverService.createPager` asks for it:
    /// items of the chosen `types`, movies and series only when they have a backdrop, in random
    /// order, rated for at most `maxAgeRating` years (`nil` for any rating). Wholphin pages through
    /// every match; the screensaver asks again for a new random set once it has shown these. With
    /// photos among the types, the backdrop isn't asked of the server, since photos have none, as
    /// in Wholphin; a movie or series without one is left out here instead. With no types, there's
    /// nothing to show and nothing is asked.
    func screensaverSlides(
        maxAgeRating: Int?,
        types: ScreensaverItemTypes = .default,
        limit: Int = 100,
    ) async throws -> [ScreensaverSlide] {
        guard !types.kinds.isEmpty else { return [] }
        var parameters = Paths.GetItemsParameters(userID: userID)
        parameters.isRecursive = true
        parameters.includeItemTypes = ScreensaverItemTypes.Kind.allCases.filter(types.contains).map(\.itemKind)
        if !types.contains(.photo) {
            parameters.imageTypes = [.backdrop]
        }
        parameters.sortBy = [.random]
        parameters.limit = limit
        // As in Wholphin: the server reads a bare number as an age, and items without a rating
        // are left out once there's a limit.
        if let maxAgeRating {
            parameters.maxOfficialRating = String(maxAgeRating)
            parameters.hasParentalRating = true
        }
        parameters.enableImageTypes = types.contains(.photo) ? [.backdrop, .logo, .primary] : [.backdrop, .logo]
        parameters.imageTypeLimit = 1
        parameters.enableTotalRecordCount = false
        let items = try await send(Paths.getItems(parameters: parameters)).items ?? []
        return items.compactMap(ScreensaverSlide.init)
    }
}

private extension ScreensaverItemTypes.Kind {
    var itemKind: BaseItemKind {
        switch self {
        case .movie: .movie
        case .series: .series
        case .photo: .photo
        }
    }
}

private extension ScreensaverSlide {
    init?(_ dto: BaseItemDto) {
        guard let id = dto.id else { return nil }
        if dto.type == .photo {
            // The photo is its own primary image, and Wholphin titles it with the day it was
            // taken, or nothing.
            guard let photo = ItemImage(itemID: id, kind: .primary, tag: dto.imageTags?[ImageType.primary.rawValue])
            else { return nil }
            self.init(id: id, title: dto.premiereDate.map(Self.dayText) ?? "", backdrop: photo)
            return
        }
        guard let backdrop = ItemImage(itemID: id, kind: .backdrop, tag: dto.backdropImageTags?.first) else {
            return nil
        }
        self.init(
            id: id,
            title: dto.name ?? "",
            backdrop: backdrop,
            logo: ItemImage(itemID: id, kind: .logo, tag: dto.imageTags?[ImageType.logo.rawValue]),
        )
    }

    /// The day a photo was taken, as Wholphin's `formatDate` writes it: the server's date is
    /// UTC, read as such so it doesn't shift with the time zone.
    static func dayText(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .long, time: .omitted, timeZone: TimeZone(identifier: "UTC") ?? .current))
    }
}
