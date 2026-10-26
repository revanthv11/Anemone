import Foundation

/// One row on the home page.
public struct HomeRow: Hashable, Identifiable, Sendable {
    public enum Kind: Hashable, Sendable {
        case continueWatching
        case nextUp
        case recentlyAdded(Library)
    }

    /// Wholphin's default for "max items per row".
    public static let defaultLimit = 25

    public let kind: Kind
    public let items: [MediaItem]

    public init(kind: Kind, items: [MediaItem]) {
        self.kind = kind
        self.items = items
    }

    public var id: String {
        switch kind {
        case .continueWatching: "continueWatching"
        case .nextUp: "nextUp"
        case let .recentlyAdded(library): "recentlyAdded.\(library.id)"
        }
    }
}

/// What the home page shows, plus the libraries for the sidebar.
public struct HomeContent: Hashable, Sendable {
    public let libraries: [Library]
    /// Rows that loaded and have something in them, in order.
    public let rows: [HomeRow]
    /// Rows that couldn't be loaded.
    public let failedRows: [HomeRow.Kind]

    public init(libraries: [Library], rows: [HomeRow], failedRows: [HomeRow.Kind]) {
        self.libraries = libraries
        self.rows = rows
        self.failedRows = failedRows
    }
}

public extension JellyfinSession {
    /// Wholphin's default home page: Continue Watching, Next Up, then Recently Added for each
    /// library. Rows load in parallel; one failing doesn't stop the others.
    ///
    /// - Throws: when the libraries can't be loaded, or `SessionError.signedOut` from any request.
    func home(itemsPerRow limit: Int = HomeRow.defaultLimit) async throws -> HomeContent {
        // These two don't need the library list, so they start without waiting for it.
        async let resumeResult = result { try await continueWatching(limit: limit) }
        async let nextUpResult = result { try await nextUp(limit: limit) }
        let libraries = try await libraries()
        let latestLibraries = libraries.filter(\.hasRecentlyAddedRow)

        let latestResults = await withTaskGroup(of: (Int, ItemsResult).self) { group in
            for (index, library) in latestLibraries.enumerated() {
                group.addTask {
                    await (index, result { try await recentlyAdded(in: library.id, limit: limit) })
                }
            }
            var results = [ItemsResult](repeating: .success([]), count: latestLibraries.count)
            for await (index, result) in group {
                results[index] = result
            }
            return results
        }

        let kinds = [HomeRow.Kind.continueWatching, .nextUp] + latestLibraries.map(HomeRow.Kind.recentlyAdded)
        let results = await [resumeResult, nextUpResult] + latestResults
        var rows: [HomeRow] = []
        var failedRows: [HomeRow.Kind] = []
        for (kind, result) in zip(kinds, results) {
            switch result {
            case let .success(items) where !items.isEmpty:
                rows.append(HomeRow(kind: kind, items: items))
            case .success:
                break
            case let .failure(error):
                if error as? SessionError == .signedOut {
                    throw SessionError.signedOut
                }
                failedRows.append(kind)
            }
        }
        return HomeContent(libraries: libraries, rows: rows, failedRows: failedRows)
    }

    private typealias ItemsResult = Result<[MediaItem], any Error>

    private func result(_ load: () async throws -> [MediaItem]) async -> ItemsResult {
        do {
            return try await .success(load())
        } catch {
            return .failure(error)
        }
    }
}
