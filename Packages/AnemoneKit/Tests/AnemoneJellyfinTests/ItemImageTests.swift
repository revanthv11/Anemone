import AnemoneJellyfin
import Testing

struct ItemImageTests {
    private let seriesPoster = ItemImage(itemID: "series", kind: .primary, tag: "sp")
    private let seriesThumb = ItemImage(itemID: "series", kind: .thumb, tag: "st")
    private let seriesBackdrop = ItemImage(itemID: "series", kind: .backdrop, tag: "sb")

    private func episode(_ artwork: MediaItem.Artwork) -> MediaItem {
        MediaItem(id: "ep", name: "Pilot", kind: .episode, artwork: artwork)
    }

    private func season(_ artwork: MediaItem.Artwork) -> MediaItem {
        MediaItem(id: "s1", name: "Season 1", kind: .season, artwork: artwork)
    }

    private func movie(_ artwork: MediaItem.Artwork) -> MediaItem {
        MediaItem(id: "m", name: "Film", kind: .movie, artwork: artwork)
    }

    @Test func `an episode thumb prefers its own thumb`() {
        let item = episode(.init(primaryTag: "still", thumbTag: "own", parentThumb: seriesThumb))

        #expect(item.thumbImage == ItemImage(itemID: "ep", kind: .thumb, tag: "own"))
    }

    @Test func `an episode thumb falls back to the series thumb, then the series backdrop`() {
        let withSeriesThumb = episode(.init(parentThumb: seriesThumb, parentBackdrop: seriesBackdrop))
        let withSeriesBackdrop = episode(.init(primaryTag: "still", parentBackdrop: seriesBackdrop))

        #expect(withSeriesThumb.thumbImage == seriesThumb)
        #expect(withSeriesBackdrop.thumbImage == seriesBackdrop)
    }

    @Test func `an episode thumb falls back to its still when the series has no art`() {
        let item = episode(.init(primaryTag: "still"))

        #expect(item.thumbImage == ItemImage(itemID: "ep", kind: .primary, tag: "still"))
    }

    @Test func `a movie thumb falls back to its backdrop, then its poster`() {
        let withBackdrop = movie(.init(primaryTag: "p", backdropTag: "b"))
        let posterOnly = movie(.init(primaryTag: "p"))

        #expect(withBackdrop.thumbImage == ItemImage(itemID: "m", kind: .backdrop, tag: "b"))
        #expect(posterOnly.thumbImage == ItemImage(itemID: "m", kind: .primary, tag: "p"))
    }

    @Test func `a movie ignores parent art`() {
        let item = movie(.init(parentThumb: seriesThumb))

        #expect(item.thumbImage == nil)
    }

    @Test func `an episode poster uses the series poster`() {
        let item = episode(.init(primaryTag: "still", seriesPrimary: seriesPoster))

        #expect(item.posterImage == seriesPoster)
    }

    @Test func `a season poster prefers its own, then the series poster`() {
        let own = season(.init(primaryTag: "own", seriesPrimary: seriesPoster))
        let none = season(.init(seriesPrimary: seriesPoster))

        #expect(own.posterImage == ItemImage(itemID: "s1", kind: .primary, tag: "own"))
        #expect(none.posterImage == seriesPoster)
    }

    @Test func `an episode backdrop is the series backdrop`() {
        let item = episode(.init(backdropTag: "own", parentBackdrop: seriesBackdrop))

        #expect(item.backdropImage == seriesBackdrop)
    }

    @Test func `no tag means no image`() {
        let item = movie(.init())

        #expect(item.posterImage == nil)
        #expect(item.thumbImage == nil)
        #expect(item.backdropImage == nil)
    }
}
