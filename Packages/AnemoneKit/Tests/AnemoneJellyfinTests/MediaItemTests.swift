import AnemoneJellyfin
import Testing

struct MediaItemTests {
    private let episode = MediaItem(
        id: "ep",
        name: "Pilot",
        kind: .episode,
        episode: .init(seriesID: "series", seriesName: "Show", seasonNumber: 1, episodeNumber: 3),
        artwork: .init(
            primaryTag: "still",
            seriesPrimary: ItemImage(itemID: "series", kind: .primary, tag: "sp"),
            parentThumb: ItemImage(itemID: "series", kind: .thumb, tag: "st"),
            parentBackdrop: ItemImage(itemID: "other", kind: .backdrop, tag: "ob"),
        ),
    )

    @Test func `episodes are titled by their series`() {
        #expect(episode.displayTitle == "Show")
        #expect(episode.episodeLabel == "S1:E3")
    }

    @Test func `a series stand-in keeps only the series' art`() throws {
        let series = try #require(episode.seriesStandIn)

        #expect(series.id == "series")
        #expect(series.name == "Show")
        #expect(series.kind == .series)
        #expect(series.artwork == .init(primaryTag: "sp", thumbTag: "st"))
    }

    @Test func `grouping replaces episodes with their series once`() {
        let movie = MediaItem(id: "m", name: "Film", kind: .movie)
        var secondEpisode = episode
        secondEpisode.name = "Second"

        let grouped = MediaItem.groupedBySeries([episode, movie, secondEpisode])

        #expect(grouped.map(\.id) == ["series", "m"])
    }

    @Test func `episodes without a series stay as they are`() {
        let orphan = MediaItem(id: "ep", name: "Pilot", kind: .episode)

        #expect(MediaItem.groupedBySeries([orphan]) == [orphan])
    }
}
