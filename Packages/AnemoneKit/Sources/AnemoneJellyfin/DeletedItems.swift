import Foundation

// What the pages behind an item's page drop once the item is deleted there, so going back finds
// it gone without loading again. `LibraryPager.remove(_:)` does the same for the library grids.

public extension MediaItem {
    /// Whether the item is one of `deleted`, or an episode of a series among them, which the
    /// server deletes along with the series.
    func wasDeleted(in deleted: Set<ID>) -> Bool {
        deleted.contains(id) || episode?.seriesID.map(deleted.contains) == true
    }
}

public extension HomeContent {
    /// The page without the deleted items' cards, and without the rows that leaves empty, as the
    /// next refresh would show it.
    func removing(_ deleted: Set<MediaItem.ID>) -> HomeContent {
        let rows = rows.compactMap { row -> HomeRow? in
            let cards = row.cards.filter { !$0.item.wasDeleted(in: deleted) }
            if cards.count == row.cards.count {
                return row
            }
            return cards.isEmpty ? nil : HomeRow(id: row.id, title: row.title, config: row.config, cards: cards)
        }
        return HomeContent(libraries: libraries, configs: configs, rows: rows, failedRows: failedRows)
    }
}

public extension RecommendedContent {
    /// The tab without the deleted items, and without the rows that leaves empty.
    func removing(_ deleted: Set<MediaItem.ID>) -> RecommendedContent {
        let rows = rows.compactMap { row -> RecommendedRow? in
            let items = row.items.filter { !$0.wasDeleted(in: deleted) }
            if items.count == row.items.count {
                return row
            }
            return items.isEmpty ? nil : RecommendedRow(kind: row.kind, items: items)
        }
        return RecommendedContent(rows: rows, failedRows: failedRows)
    }
}

public extension FavoritesContent {
    /// The page without the deleted items, and without the rows that leaves empty.
    func removing(_ deleted: Set<MediaItem.ID>) -> FavoritesContent {
        let sections = sections.compactMap { section -> FavoritesSection? in
            let items = section.items.filter { !$0.item.wasDeleted(in: deleted) }
            if items.count == section.items.count {
                return section
            }
            return items.isEmpty ? nil : FavoritesSection(kind: section.kind, items: items)
        }
        return FavoritesContent(sections: sections, failedKinds: failedKinds)
    }
}

public extension SearchResults {
    /// Takes the deleted items out of the rows and the combined grid, which keep the rest.
    mutating func remove(_ deleted: Set<MediaItem.ID>) {
        rows = rows.mapValues { $0.removing(deleted) }
        combined = combined.map { CombinedSearch(kinds: $0.kinds, state: $0.state.removing(deleted)) }
    }
}

private extension SearchResults.State {
    func removing(_ deleted: Set<MediaItem.ID>) -> Self {
        guard case let .found(items) = self else { return self }
        return .found(items.filter { !$0.item.wasDeleted(in: deleted) })
    }
}
