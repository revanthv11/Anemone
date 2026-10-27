import Foundation

/// A tab along the top of a library's page, from Wholphin's `CollectionFolderMovie` and
/// `CollectionFolderTv`. The raw value is what's saved when the app remembers a library's tab.
public enum LibrarySection: String, CaseIterable, Hashable, Sendable {
    /// Rows of what to watch: Continue Watching, Next Up, new and unwatched titles, suggestions.
    case recommended
    /// The library's grid.
    case library
    /// The collections holding the library's movies.
    case collections
    case genres
    /// The studios and networks behind a TV library's series.
    case studios
}

public extension Library {
    /// The tabs on the library's page, in Wholphin's order. Other kinds of library have only
    /// their grid, so their page has no tabs.
    var sections: [LibrarySection] {
        switch kind {
        case .movies: [.recommended, .library, .collections, .genres]
        case .shows: [.recommended, .library, .genres, .studios]
        default: [.library]
        }
    }

    /// The tab the page opens on: the remembered one, as Wholphin's `RememberedTabService` keeps
    /// it, when the library still has that tab; otherwise the first.
    func startingSection(remembered: String?) -> LibrarySection {
        let tabs = sections
        return remembered.flatMap(LibrarySection.init(rawValue:)).flatMap { tabs.contains($0) ? $0 : nil } ?? tabs[0]
    }
}
