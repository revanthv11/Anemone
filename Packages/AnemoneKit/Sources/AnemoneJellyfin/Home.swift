import AnemoneCore
import Foundation
import Get

/// One row on the home page, loaded.
public struct HomeRow: Hashable, Identifiable, Sendable {
    /// Wholphin's default for "max items per row".
    public static let defaultLimit = 25

    /// Stable across reloads; see `HomeRowConfig.rowIDs(for:)`.
    public let id: String
    public let title: String
    public let config: HomeRowConfig
    public let cards: [HomeCard]

    public init(id: String, title: String, config: HomeRowConfig, cards: [HomeCard]) {
        self.id = id
        self.title = title
        self.config = config
        self.cards = cards
    }

    public var items: [MediaItem] {
        cards.map(\.item)
    }
}

/// A card on a home row: an item, or a genre or studio, which opens its items in a grid.
public struct HomeCard: Hashable, Identifiable, Sendable {
    public enum Destination: Hashable, Sendable {
        /// The item's own page.
        case item
        case items(HomeItemsLink)
    }

    /// For a genre or studio, an item holding its ID and name.
    public let item: MediaItem
    /// Art in place of the item's own: a genre shows a backdrop from one of its items.
    public let image: ItemImage?
    public let destination: Destination

    public init(item: MediaItem, image: ItemImage? = nil, destination: Destination = .item) {
        self.item = item
        self.image = image
        self.destination = destination
    }

    public var id: MediaItem.ID {
        item.id
    }
}

/// A genre's or a studio's items in one library, which its card opens, as Wholphin's genre and
/// studio destinations do.
public struct HomeItemsLink: Hashable, Sendable {
    public let title: String
    public let query: LibraryQuery

    public init(title: String, query: LibraryQuery) {
        self.title = title
        self.query = query
    }
}

/// What the home page shows, plus the libraries for the sidebar.
public struct HomeContent: Hashable, Sendable {
    public let libraries: [Library]
    /// Every configured row, including those with nothing in them.
    public let configs: [HomeRowConfig]
    /// Rows that loaded and have something in them, in order.
    public let rows: [HomeRow]
    /// The IDs of rows that couldn't be loaded.
    public let failedRows: [String]

    public init(libraries: [Library], configs: [HomeRowConfig], rows: [HomeRow], failedRows: [String]) {
        self.libraries = libraries
        self.configs = configs
        self.rows = rows
        self.failedRows = failedRows
    }
}

/// Settings and helpers for loading the home page.
public struct HomeOptions: Sendable {
    /// Wholphin's "Max items on home page rows".
    public var itemsPerRow: Int
    /// Wholphin's "Enable rewatching in next up".
    public var enableRewatchingNextUp: Bool
    /// Wholphin's "Max days in Next Up"; 0 or less for no limit.
    public var maxDaysNextUp: Int
    public var liveTV: any HomeLiveTVSource
    public var cache: HomeCache
    /// Whether the page is already showing, so picks made at random, such as a genre's art, stay.
    public var isRefresh: Bool

    public init(
        itemsPerRow: Int = HomeRow.defaultLimit,
        enableRewatchingNextUp: Bool = false,
        maxDaysNextUp: Int = -1,
        liveTV: any HomeLiveTVSource = NoLiveTV(),
        cache: HomeCache = HomeCache(),
        isRefresh: Bool = false,
    ) {
        self.itemsPerRow = itemsPerRow
        self.enableRewatchingNextUp = enableRewatchingNextUp
        self.maxDaysNextUp = maxDaysNextUp
        self.liveTV = liveTV
        self.cache = cache
        self.isRefresh = isRefresh
    }
}

/// What the home page keeps between loads: the dates the combined row sorts by, suggestions,
/// and the art picked for genres.
public actor HomeCache {
    private var datePlayed: [String: (date: Date, expiry: Date)] = [:]
    private var suggestions: [String: (ids: [String], expiry: Date)] = [:]
    private var genreArt: [String: GenreArt] = [:]

    public init() {}

    func datePlayed(for key: String, now: Date = .now) -> Date? {
        datePlayed[key].flatMap { $0.expiry > now ? $0.date : nil }
    }

    /// Kept for two hours, as Wholphin's `DatePlayedService` keeps them.
    func setDatePlayed(_ date: Date, for key: String, now: Date = .now) {
        datePlayed[key] = (date, now.addingTimeInterval(2 * 3600))
    }

    func suggestions(for key: String, now: Date = .now) -> [String]? {
        suggestions[key].flatMap { $0.expiry > now ? $0.ids : nil }
    }

    /// Kept for twelve hours, Wholphin's interval for working out suggestions again.
    func setSuggestions(_ ids: [String], for key: String, now: Date = .now) {
        suggestions[key] = (ids, now.addingTimeInterval(12 * 3600))
    }

    func genreArt(for parentID: String) -> GenreArt? {
        genreArt[parentID]
    }

    func setGenreArt(_ art: GenreArt, for parentID: String) {
        genreArt[parentID] = art
    }
}

/// The art picked for a library's genres, and which genres were looked up, since some have no
/// item with a backdrop.
struct GenreArt: Sendable {
    var images: [String: ItemImage] = [:]
    var lookedUp: Set<String> = []
}

public extension JellyfinSession {
    /// Loads the home page's rows, as Wholphin's `HomeViewModel.loadHomeRows`: four at a time,
    /// one failing doesn't stop the others, and a row whose library is gone (a 404) is empty.
    ///
    /// - Parameter configs: the rows to show; Wholphin's default rows when `nil`.
    /// - Throws: when the libraries can't be loaded, or `SessionError.signedOut` from any request.
    func home(rows configs: [HomeRowConfig]? = nil, options: HomeOptions = HomeOptions()) async throws -> HomeContent {
        let needsRemoved = configs?.contains { $0.kind == .nextUp || $0.kind == .continueWatchingCombined } ?? true
        async let removedResult = needsRemoved ? attempt { try await removedFromNextUp() } : .success(.init())
        let libraries = try await libraries()
        let configs = configs ?? HomePageSettings.defaultRows(for: libraries)
        // A failed read shows every series, as if none were removed.
        let removed = await (try? removedResult.get()) ?? RemovedFromNextUp()
        let context = HomeRowContext(libraries: libraries, options: options, removed: removed)

        let results = await boundedMap(configs.count, width: 4) { index in
            await attempt { try await homeRowData(configs[index], context: context) }
        }

        let ids = HomeRowConfig.rowIDs(for: configs)
        var rows: [HomeRow] = []
        var failedRows: [String] = []
        for (index, result) in results.enumerated() {
            let config = configs[index]
            switch result {
            case let .success(data) where !data.cards.isEmpty:
                let title = data.title ?? config.title(libraries: libraries)
                rows.append(HomeRow(id: ids[index], title: title, config: config, cards: data.cards))
            case .success, .failure(APIError.unacceptableStatusCode(404)):
                break
            case let .failure(error):
                if error as? SessionError == .signedOut {
                    throw SessionError.signedOut
                }
                failedRows.append(ids[index])
            }
        }
        return HomeContent(libraries: libraries, configs: configs, rows: rows, failedRows: failedRows)
    }
}

/// What every row's request shares.
struct HomeRowContext: Sendable {
    let libraries: [Library]
    let options: HomeOptions
    let removed: RemovedFromNextUp

    var limit: Int {
        options.itemsPerRow
    }

    func library(_ id: String) -> Library? {
        libraries.first { $0.id == id }
    }
}

/// A row's cards, and its title when it depends on what the server says.
struct HomeRowData: Sendable {
    var cards: [HomeCard]
    var title: String?

    init(cards: [HomeCard], title: String? = nil) {
        self.cards = cards
        self.title = title
    }

    init(items: [MediaItem], title: String? = nil) {
        self.init(cards: items.map { HomeCard(item: $0) }, title: title)
    }
}

/// Runs a request and keeps its error, so several can run at once and be checked afterwards.
func attempt<Value: Sendable>(_ request: () async throws -> Value) async -> Result<Value, any Error> {
    do {
        return try await .success(request())
    } catch {
        return .failure(error)
    }
}

/// `work` for each index, at most `width` at a time, with the results in index order.
func boundedMap<Value: Sendable>(
    _ count: Int,
    width: Int,
    _ work: @escaping @Sendable (Int) async -> Value,
) async -> [Value] {
    await withTaskGroup(of: (Int, Value).self) { group in
        var next = 0
        func addNext() {
            guard next < count else { return }
            let index = next
            next += 1
            group.addTask { await (index, work(index)) }
        }
        for _ in 0 ..< width {
            addNext()
        }
        var results = [Value?](repeating: nil, count: count)
        while let (index, value) = await group.next() {
            results[index] = value
            addNext()
        }
        return results.compactMap(\.self)
    }
}
