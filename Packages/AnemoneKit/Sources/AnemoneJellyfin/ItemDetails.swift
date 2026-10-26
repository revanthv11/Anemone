import Foundation
import JellyfinAPI

/// What an item page shows about an item, beyond what a card needs.
///
/// Rows on item pages (seasons, episodes, collection and playlist entries, a filmography) hold
/// these too, so focusing one can show its details. Only `itemDetails(id:)` and episode lists
/// come with `people`.
public struct ItemDetails: Hashable, Identifiable, Sendable {
    /// The signed-in user's history with the item.
    public struct UserState: Hashable, Sendable {
        public var isPlayed: Bool
        public var isFavorite: Bool
        /// Where playback would resume; `nil` to start from the beginning.
        public var resumePosition: Duration?
        /// For series, seasons and collections: how many of their episodes or items are unwatched.
        public var unplayedCount: Int?
        /// How much has been watched, from 0 to 1, as `MediaItem.progress` holds it.
        public var progress: Double?

        public init(
            isPlayed: Bool = false,
            isFavorite: Bool = false,
            resumePosition: Duration? = nil,
            unplayedCount: Int? = nil,
            progress: Double? = nil,
        ) {
            self.isPlayed = isPlayed
            self.isFavorite = isFavorite
            self.resumePosition = resumePosition
            self.unplayedCount = unplayedCount
            self.progress = progress
        }
    }

    /// How many items a person is credited in, by type. `nil` when the server didn't say.
    public struct CreditCounts: Hashable, Sendable {
        public var movies: Int?
        public var series: Int?
        public var episodes: Int?

        public init(movies: Int? = nil, series: Int? = nil, episodes: Int? = nil) {
            self.movies = movies
            self.series = series
            self.episodes = episodes
        }
    }

    public var item: MediaItem
    /// The first tagline, such as "In space no one can hear you scream."
    public var tagline: String?
    public var genres: [String]
    public var studios: [String]
    /// Cast and crew in the server's order.
    public var people: [Credit]
    /// Out of 10.
    public var communityRating: Double?
    /// A percentage, from 0 to 100.
    public var criticRating: Double?
    /// When a movie or episode was released, or when a person was born.
    public var premiereDate: Date?
    /// When a series ended, or when a person died.
    public var endDate: Date?
    /// For series: whether new episodes are still coming. `nil` when unknown.
    public var isContinuing: Bool?
    /// For seasons, the number of episodes; for collections and playlists, the number of items.
    public var childCount: Int?
    public var userState: UserState
    /// The item's logo; for episodes and seasons, the series logo.
    public var logo: ItemImage?
    /// For episodes, the season they're in.
    public var seasonID: String?
    /// For people.
    public var birthPlace: String?
    /// For people.
    public var creditCounts: CreditCounts
    /// Width over height of the item's primary image.
    public var primaryImageAspectRatio: Double?

    public init(
        item: MediaItem,
        tagline: String? = nil,
        genres: [String] = [],
        studios: [String] = [],
        people: [Credit] = [],
        communityRating: Double? = nil,
        criticRating: Double? = nil,
        premiereDate: Date? = nil,
        endDate: Date? = nil,
        isContinuing: Bool? = nil,
        childCount: Int? = nil,
        userState: UserState = UserState(),
        logo: ItemImage? = nil,
        seasonID: String? = nil,
        birthPlace: String? = nil,
        creditCounts: CreditCounts = CreditCounts(),
        primaryImageAspectRatio: Double? = nil,
    ) {
        self.item = item
        self.tagline = tagline
        self.genres = genres
        self.studios = studios
        self.people = people
        self.communityRating = communityRating
        self.criticRating = criticRating
        self.premiereDate = premiereDate
        self.endDate = endDate
        self.isContinuing = isContinuing
        self.childCount = childCount
        self.userState = userState
        self.logo = logo
        self.seasonID = seasonID
        self.birthPlace = birthPlace
        self.creditCounts = creditCounts
        self.primaryImageAspectRatio = primaryImageAspectRatio
    }

    public var id: MediaItem.ID {
        item.id
    }

    /// Takes the user's new state from the server, keeping the card's progress bar in step:
    /// marking an item watched clears its resume position and progress.
    public mutating func apply(_ state: UserState) {
        userState = state
        item.progress = state.progress
    }

    /// A season's or episode's number within its parent.
    public var indexNumber: Int? {
        switch item.kind {
        case .season: item.episode?.seasonNumber
        case .episode: item.episode?.episodeNumber
        default: nil
        }
    }

    /// How much is left to watch, when there's a resume position.
    public var timeRemaining: Duration? {
        guard let position = userState.resumePosition, let runtime = item.runtime, runtime > position else {
            return nil
        }
        return runtime - position
    }

    /// "2008 - 2013" for a series that ended, "2008 - Present" for one still running, like
    /// Wholphin. Just the year when the series ended the year it started, or its status is unknown.
    public var seriesYears: String? {
        guard let start = item.year else { return nil }
        switch isContinuing {
        case true?:
            return "\(start) - Present"
        case false?:
            guard let end = endDate.map({ Self.calendar.component(.year, from: $0) }), end != start else {
                return "\(start)"
            }
            return "\(start) - \(end)"
        case nil:
            return "\(start)"
        }
    }

    /// A person's age in whole years: when they died, or now.
    public func age(now: Date = .now) -> Int? {
        guard let born = premiereDate else { return nil }
        return Self.calendar.dateComponents([.year], from: born, to: endDate ?? now).year
    }

    /// The people credited with directing, for "Directed by".
    public var directors: [String] {
        people.filter { $0.kind == .director && !$0.name.isEmpty }.map(\.name)
    }

    /// The item's own primary image, such as an episode's still. Cards in episode lists use this
    /// rather than the series art that `MediaItem.thumbImage` prefers.
    public var ownPrimaryImage: ItemImage? {
        ItemImage(itemID: item.id, kind: .primary, tag: item.artwork.primaryTag)
    }

    /// Server dates are UTC; the year is read in UTC so it doesn't shift with the time zone.
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()
}

/// Someone in an item's cast or crew.
public struct Credit: Hashable, Identifiable, Sendable {
    public enum Kind: Hashable, Sendable {
        case actor
        case guestStar
        case director
        case writer
        case producer
        case composer
        case creator
        case other
    }

    public let personID: String
    public let name: String
    public let kind: Kind
    /// The character for actors and guest stars, otherwise the job, such as "Director" or
    /// "Screenplay - Writer".
    public let role: String?
    public let image: ItemImage?

    public init(personID: String, name: String, kind: Kind, role: String?, image: ItemImage? = nil) {
        self.personID = personID
        self.name = name
        self.kind = kind
        self.role = role
        self.image = image
    }

    /// The same person can be credited more than once, for different jobs.
    public var id: String {
        "\(personID)|\(kind)|\(role ?? "")"
    }

    /// The person, to open their page.
    public var person: MediaItem {
        MediaItem(id: personID, name: name, kind: .person, artwork: .init(primaryTag: image?.tag))
    }
}

extension ItemDetails {
    init?(_ dto: BaseItemDto) {
        guard let item = MediaItem(dto) else { return nil }
        let isContinuing: Bool? = switch dto.status {
        case "Continuing": true
        case "Ended": false
        default: nil
        }
        // Episodes and seasons show their series' logo, as Wholphin's `rememberLogoUrl` does.
        let logo = switch item.kind {
        case .episode, .season:
            ItemImage(itemID: dto.parentLogoItemID, kind: .logo, tag: dto.parentLogoImageTag)
        default:
            ItemImage(itemID: dto.id, kind: .logo, tag: dto.imageTags?[ImageType.logo.rawValue])
        }
        var seen = Set<String>()
        self.init(
            item: item,
            tagline: dto.taglines?.first { !$0.isEmpty },
            genres: dto.genres ?? [],
            studios: dto.studios?.compactMap(\.name) ?? [],
            people: (dto.people ?? []).compactMap(Credit.init).filter { seen.insert($0.id).inserted },
            communityRating: dto.communityRating.map(Double.init),
            criticRating: dto.criticRating.map(Double.init),
            premiereDate: dto.premiereDate,
            endDate: dto.endDate,
            isContinuing: isContinuing,
            childCount: dto.childCount,
            userState: UserState(dto.userData),
            logo: logo,
            seasonID: dto.seasonID,
            birthPlace: dto.productionLocations?.first { !$0.isEmpty },
            creditCounts: CreditCounts(movies: dto.movieCount, series: dto.seriesCount, episodes: dto.episodeCount),
            primaryImageAspectRatio: dto.primaryImageAspectRatio,
        )
    }
}

extension ItemDetails.UserState {
    init(_ data: UserItemDataDto?) {
        self.init(
            isPlayed: data?.isPlayed ?? false,
            isFavorite: data?.isFavorite ?? false,
            // Jellyfin counts in 100-nanosecond ticks.
            resumePosition: data?.playbackPositionTicks.flatMap { $0 > 0 ? .microseconds($0 / 10) : nil },
            unplayedCount: data?.unplayedItemCount,
            // The same reading as `MediaItem.progress`.
            progress: data?.playedPercentage.flatMap { $0 > 0 ? min($0 / 100, 1) : nil },
        )
    }
}

extension Credit {
    init?(_ dto: BaseItemPerson) {
        guard let id = dto.id, let name = dto.name else { return nil }
        let kind = dto.type ?? .unknown
        self.init(
            personID: id,
            name: name,
            kind: Kind(kind),
            role: Self.role(dto.role, kind: kind),
            image: ItemImage(itemID: id, kind: .primary, tag: dto.primaryImageTag),
        )
    }

    /// Ported from Wholphin's `personRole`: actors keep their character; crew get their job,
    /// joined to the credited role when that doesn't already say it.
    static func role(_ role: String?, kind: PersonKind) -> String? {
        let role = role.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        switch kind {
        case .actor, .guestStar, .unknown:
            return role
        default:
            let job = jobTitles[kind]
            guard let role else { return job }
            if role.caseInsensitiveCompare(kind.rawValue) == .orderedSame {
                return job ?? role
            }
            if role.localizedCaseInsensitiveContains(kind.rawValue) {
                return role
            }
            return [role, job].compactMap(\.self).joined(separator: " - ")
        }
    }

    private static let jobTitles: [PersonKind: String] = [
        .director: "Director",
        .composer: "Composer",
        .writer: "Writer",
        .producer: "Producer",
        .conductor: "Conductor",
        .lyricist: "Lyricist",
        .arranger: "Arranger",
        .engineer: "Engineer",
        .mixer: "Mixer",
        .remixer: "Mixer",
        .creator: "Creator",
        .artist: "Artist",
        .albumArtist: "Artist",
    ]
}

private extension Credit.Kind {
    init(_ kind: PersonKind) {
        self = switch kind {
        case .actor: .actor
        case .guestStar: .guestStar
        case .director: .director
        case .writer: .writer
        case .producer: .producer
        case .composer: .composer
        case .creator: .creator
        default: .other
        }
    }
}
