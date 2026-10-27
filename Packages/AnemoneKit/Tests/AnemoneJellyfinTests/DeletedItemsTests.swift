import AnemoneCore
import AnemoneJellyfin
import Testing

/// What the pages behind a deleted item's page drop when it's gone, without loading again.
struct DeletedItemsTests {
    private let movie = MediaItem(id: "m1", name: "Deletable One", kind: .movie)
    private let other = MediaItem(id: "m2", name: "Deletable Two", kind: .movie)
    private let episode = MediaItem(
        id: "e1",
        name: "Pilot",
        kind: .episode,
        episode: MediaItem.Episode(seriesID: "s1", seriesName: "Fixture Show", seasonNumber: 1, episodeNumber: 1),
    )

    @Test func `an episode goes with its deleted series`() {
        #expect(movie.wasDeleted(in: ["m1"]))
        #expect(!movie.wasDeleted(in: ["m2"]))
        #expect(episode.wasDeleted(in: ["s1"]))
        #expect(episode.wasDeleted(in: ["e1"]))
        #expect(!episode.wasDeleted(in: ["m1"]))
    }

    @Test func `home drops the deleted item's cards, and rows left empty`() {
        let recentlyAdded = HomeRow(
            id: "recentlyAdded.scratch",
            title: "Recently Added in Scratch",
            config: HomeRowConfig(.recentlyAdded(parentID: "scratch")),
            cards: [HomeCard(item: other), HomeCard(item: movie)],
        )
        let nextUp = HomeRow(
            id: "nextUp",
            title: "Next Up",
            config: HomeRowConfig(.nextUp),
            cards: [HomeCard(item: episode)],
        )
        let home = HomeContent(
            libraries: [Library(id: "scratch", name: "Scratch", kind: .movies)],
            configs: [recentlyAdded.config, nextUp.config],
            rows: [nextUp, recentlyAdded],
            failedRows: ["favorites"],
        )

        let afterMovie = home.removing(["m1"])
        #expect(afterMovie.rows.map(\.id) == ["nextUp", "recentlyAdded.scratch"])
        #expect(afterMovie.rows[1].items == [other])
        #expect(afterMovie.rows[1].title == "Recently Added in Scratch")
        #expect(afterMovie.libraries == home.libraries)
        #expect(afterMovie.configs == home.configs)
        #expect(afterMovie.failedRows == ["favorites"])

        // Deleting the series takes Next Up's only card, and with it the row.
        let afterSeries = afterMovie.removing(["s1"])
        #expect(afterSeries.rows.map(\.id) == ["recentlyAdded.scratch"])
        #expect(home.removing(["elsewhere"]) == home)
    }

    @Test func `a library's recommended rows drop the deleted item`() {
        let recommended = RecommendedContent(
            rows: [
                RecommendedRow(kind: .recentlyAdded, items: [other, movie]),
                RecommendedRow(kind: .suggestions, items: [movie]),
            ],
            failedRows: [.topUnwatched],
        )

        let after = recommended.removing(["m1"])

        #expect(after.rows == [RecommendedRow(kind: .recentlyAdded, items: [other])])
        #expect(after.failedRows == [.topUnwatched])
        #expect(recommended.removing(["elsewhere"]) == recommended)
    }

    @Test func `favorites drop the deleted item, and rows left empty`() {
        let favorites = FavoritesContent(
            sections: [
                FavoritesSection(kind: .movie, items: [ItemDetails(item: movie), ItemDetails(item: other)]),
                FavoritesSection(kind: .episode, items: [ItemDetails(item: episode)]),
            ],
            failedKinds: [.series],
        )

        let after = favorites.removing(["m1", "s1"])

        #expect(after.sections == [FavoritesSection(kind: .movie, items: [ItemDetails(item: other)])])
        #expect(after.failedKinds == [.series])
    }

    @Test func `search results drop the deleted item from their rows and grid`() {
        var results = SearchResults(term: "deletable")
        results.record(.found([ItemDetails(item: movie), ItemDetails(item: other)]), for: .movie)
        results.record(.found([ItemDetails(item: episode)]), for: .episode)
        results.record(.searching, for: .series)
        results.combined = CombinedSearch(kinds: [.movie], state: .found([ItemDetails(item: movie)]))

        results.remove(["m1"])

        #expect(results.rows[.movie] == .found([ItemDetails(item: other)]))
        #expect(results.rows[.episode] == .found([ItemDetails(item: episode)]))
        #expect(results.rows[.series] == .searching)
        #expect(results.combined == CombinedSearch(kinds: [.movie], state: .found([])))
        #expect(results.term == "deletable")
    }
}
