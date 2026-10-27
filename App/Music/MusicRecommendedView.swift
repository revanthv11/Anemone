import AnemoneCore
import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// A music library's Recommended tab, Wholphin's `RecommendedMusic`: rows of recently released,
/// recently added and top rated albums, then Wholphin's suggestions. Rows that come back empty
/// or fail are left out.
struct MusicRecommendedView: View {
    let library: Library

    private enum Row: Hashable, CaseIterable {
        case recentlyReleased
        case recentlyAdded
        case topRated
        case suggestions

        var title: String {
            switch self {
            case .recentlyReleased: MusicRecommendation.recentlyReleased.title
            case .recentlyAdded: MusicRecommendation.recentlyAdded.title
            case .topRated: MusicRecommendation.topRated.title
            case .suggestions: "Suggestions"
            }
        }

        var id: String {
            "\(self)"
        }
    }

    @Environment(BrowseModel.self) private var browse
    @FocusState private var focus: MusicFocus?
    @State private var rows: [Row: [MusicItem]] = [:]
    @State private var loaded = false

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(Row.allCases, id: \.self) { row in
                    if let items = rows[row], !items.isEmpty {
                        MusicRow(id: row.id, title: row.title, items: items, focus: $focus)
                    }
                }
                if loaded, rows.values.allSatisfy(\.isEmpty) {
                    Text("Nothing to recommend in \(library.name) yet.")
                        .foregroundStyle(.secondary)
                        .focusable()
                } else if !loaded {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, GridLayout.horizontalInset)
            .padding(.vertical, GridLayout.focusPadding)
        }
        .task(id: library.id) {
            await load()
        }
    }

    private func load() async {
        let session = browse.session
        let libraryID = library.id
        let limit = Preferences.maxItemsPerRow.value()
        await withTaskGroup(of: (Row, [MusicItem]?).self) { group in
            for row in Row.allCases {
                group.addTask {
                    let result = await attempt {
                        switch row {
                        case .recentlyReleased:
                            try await session.recommendedAlbums(.recentlyReleased, in: libraryID, limit: limit)
                        case .recentlyAdded:
                            try await session.recommendedAlbums(.recentlyAdded, in: libraryID, limit: limit)
                        case .topRated:
                            try await session.recommendedAlbums(.topRated, in: libraryID, limit: limit)
                        case .suggestions:
                            try await session.musicSuggestions(in: libraryID, limit: limit)
                        }
                    }
                    return (row, try? result.get())
                }
            }
            for await (row, items) in group {
                rows[row] = items ?? []
            }
        }
        loaded = true
    }
}

/// A music library's Genres tab, Wholphin's `GenreCardGrid`: each genre with an album's cover,
/// opening its albums.
struct MusicGenresView: View {
    let library: Library

    @Environment(BrowseModel.self) private var browse
    @Environment(\.displayScale) private var displayScale
    @State private var genres: [MusicGenre]?
    @State private var problem: String?

    private static let columns = Array(repeating: GridItem(.fixed(240), spacing: 40, alignment: .top), count: 6)

    var body: some View {
        ScrollView(.vertical) {
            if let genres {
                LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 40) {
                    ForEach(Array(genres.enumerated()), id: \.element.id) { index, genre in
                        NavigationLink(value: MusicGenreLink(id: genre.id, name: genre.name, libraryID: library.id)) {
                            MediaCard(
                                title: genre.name,
                                imageURL: browse.imageURL(genre.image, width: 240 * displayScale),
                                shape: .square,
                                width: 240,
                            )
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("music.genre.\(index)")
                    }
                }
                .padding(.horizontal, GridLayout.horizontalInset)
                .padding(.vertical, GridLayout.focusPadding)
                if genres.isEmpty {
                    Text("No genres in \(library.name).")
                        .foregroundStyle(.secondary)
                        .focusable()
                }
            } else if let problem {
                Text(problem)
                    .foregroundStyle(.secondary)
                    .focusable()
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .task(id: library.id) {
            let session = browse.session
            let id = library.id
            switch await attempt({ try await session.musicGenres(in: id) }) {
            case let .success(list):
                genres = list
            case let .failure(error):
                problem = browse.problem(with: error, doing: "load the genres from \(browse.server.name)")
            }
        }
    }
}
