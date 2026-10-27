import AnemoneJellyfin
import Testing

/// What a card's long-press menu offers, after Wholphin's `buildContextMenuItems`.
struct ItemMenuTests {
    private let movie = MediaItem(id: "m1", name: "Film", kind: .movie)
    private let episode = MediaItem(
        id: "e1",
        name: "Pilot",
        kind: .episode,
        episode: .init(seriesID: "s1", seriesName: "Show", seasonNumber: 1, episodeNumber: 1),
    )

    @Test func `a movie offers Wholphin's entries in its order`() {
        let entries = movie.menuEntries(state: ItemMenuState(isPlayed: false, isFavorite: false))

        #expect(entries == [.goTo, .play, .addToPlaylist, .setPlayed(true), .setFavorite(true)])
    }

    @Test func `a started item offers Resume and Restart instead of Play`() {
        let entries = movie.menuEntries(state: ItemMenuState(isPlayed: false, isFavorite: true, isResumable: true))

        #expect(entries == [.goTo, .resume, .restart, .addToPlaylist, .setPlayed(true), .setFavorite(false)])
    }

    @Test func `a watched favourite offers the opposite of both`() {
        let entries = movie.menuEntries(state: ItemMenuState(isPlayed: true, isFavorite: true))

        #expect(entries.suffix(2) == [.setPlayed(false), .setFavorite(false)])
    }

    @Test func `an item whose state is unknown offers both ways`() {
        let entries = movie.menuEntries(state: ItemMenuState())

        #expect(entries.suffix(4) == [.setPlayed(true), .setPlayed(false), .setFavorite(true), .setFavorite(false)])
    }

    @Test func `an episode goes to its series last`() throws {
        let series = try #require(episode.seriesStandIn)

        let entries = episode.menuEntries(state: ItemMenuState(isPlayed: false, isFavorite: false))

        #expect(entries.first == .goTo)
        #expect(entries.last == .goToSeries(series))
        #expect(series.id == "s1")
    }

    @Test func `a page that can't open others leaves out Go to`() throws {
        let series = try #require(episode.seriesStandIn)

        let entries = episode.menuEntries(state: ItemMenuState(isPlayed: false, isFavorite: false), canGoTo: false)

        #expect(!entries.contains(.goTo))
        #expect(!entries.contains(.goToSeries(series)))
    }

    @Test func `series, collections and songs aren't played from the menu`() {
        for kind: MediaItem.Kind in [.series, .season, .collection, .playlist, .musicAlbum, .audio] {
            let entries = MediaItem(id: "x", name: "X", kind: kind).menuEntries(state: ItemMenuState(isResumable: true))
            #expect(!entries.contains(.play) && !entries.contains(.resume), "\(kind)")
            #expect(entries.contains(.addToPlaylist), "\(kind)")
        }
    }

    @Test func `songs have no Go to`() {
        let song = MediaItem(id: "a1", name: "Song", kind: .audio)

        #expect(!song.menuEntries(state: ItemMenuState()).contains(.goTo))
    }

    @Test func `people only go to their page and change favourites`() {
        let person = MediaItem(id: "p1", name: "Actor", kind: .person)

        #expect(person.menuEntries(state: ItemMenuState(isFavorite: false)) == [.goTo, .setFavorite(true)])
        #expect(person.menuEntries(state: ItemMenuState(isFavorite: true), canGoTo: false) == [.setFavorite(false)])
    }

    @Test func `started, unwatched items can leave Continue Watching`() {
        let started = ItemMenuState(isPlayed: false, isFavorite: false, isResumable: true)
        let unknown = ItemMenuState(isResumable: true)

        #expect(movie.menuEntries(state: started, source: .continueWatching).contains(.removeFromContinueWatching))
        #expect(movie.menuEntries(state: unknown, source: .continueWatchingAndNextUp)
            .contains(.removeFromContinueWatching))
        #expect(!movie.menuEntries(state: started).contains(.removeFromContinueWatching))
        #expect(!movie.menuEntries(state: ItemMenuState(isPlayed: false), source: .continueWatching)
            .contains(.removeFromContinueWatching))
    }

    @Test func `episodes of a series can leave Next Up`() throws {
        let state = ItemMenuState(isPlayed: false, isFavorite: false)
        let loose = MediaItem(id: "e2", name: "Loose", kind: .episode)
        let series = try #require(episode.seriesStandIn)

        let entries = episode.menuEntries(state: state, source: .nextUp)

        #expect(entries == [
            .goTo, .play, .addToPlaylist, .removeFromNextUp, .setPlayed(true), .setFavorite(true),
            .goToSeries(series),
        ])
        #expect(!movie.menuEntries(state: state, source: .nextUp).contains(.removeFromNextUp))
        #expect(!loose.menuEntries(state: state, source: .nextUp).contains(.removeFromNextUp))
        #expect(!episode.menuEntries(state: state, source: .continueWatching).contains(.removeFromNextUp))
    }

    @Test func `details know the user's state`() {
        let details = ItemDetails(
            item: movie,
            userState: .init(isPlayed: true, isFavorite: false, resumePosition: .seconds(90)),
        )

        #expect(details.menuState == ItemMenuState(isPlayed: true, isFavorite: false, isResumable: true))
    }
}
