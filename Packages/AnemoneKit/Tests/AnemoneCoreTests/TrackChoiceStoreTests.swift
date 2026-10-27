import AnemoneCore
import Foundation
import Testing

/// Remembering track choices per item and per season and series.
struct TrackChoiceStoreTests {
    private let defaults: UserDefaults

    init() throws {
        let suite = "TrackChoiceStoreTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func `an item's choice is kept for its user only`() {
        let store = TrackChoiceStore(userID: "u1", defaults: defaults)
        let choice = ItemTrackChoice(itemID: "m1", mediaSourceID: "s1", audioIndex: 2, subtitle: .onlyForced)

        store.save(choice)

        #expect(store.itemChoice(for: "m1") == choice)
        #expect(store.itemChoice(for: "m2") == nil)
        #expect(TrackChoiceStore(userID: "u2", defaults: defaults).itemChoice(for: "m1") == nil)
        // Survives a new store, as after a relaunch.
        #expect(TrackChoiceStore(userID: "u1", defaults: defaults).itemChoice(for: "m1") == choice)
    }

    @Test func `saving again replaces the item's choice`() {
        let store = TrackChoiceStore(userID: "u1", defaults: defaults)
        store.save(ItemTrackChoice(itemID: "m1", mediaSourceID: nil, audioIndex: 1))
        store.save(ItemTrackChoice(itemID: "m1", mediaSourceID: nil, audioIndex: 1, subtitle: .off))

        #expect(store.itemChoice(for: "m1")?.subtitle == .off)
    }

    @Test func `a season's choice comes before its series', and kinds stay apart`() {
        let store = TrackChoiceStore(userID: "u1", defaults: defaults)
        let series = SeriesTrackChoice(parentID: "show", parent: .series, kind: .subtitle, language: "eng")
        let season = SeriesTrackChoice(parentID: "s2", parent: .season, kind: .subtitle, activation: .disabled)
        let audio = SeriesTrackChoice(parentID: "show", parent: .series, kind: .audio, language: "jpn")
        store.save(series)
        store.save(season)
        store.save(audio)

        #expect(store.seriesChoices(.subtitle, seriesID: "show", seasonID: "s2") == [season, series])
        #expect(store.seriesChoices(.subtitle, seriesID: "show", seasonID: "s1") == [series])
        #expect(store.seriesChoices(.audio, seriesID: "show", seasonID: "s2") == [audio])
        #expect(store.seriesChoices(.audio, seriesID: nil, seasonID: nil).isEmpty)
    }

    @Test func `only the most recent choices are kept`() {
        let store = TrackChoiceStore(userID: "u1", defaults: defaults)
        for number in 0 ... TrackChoiceStore.itemLimit {
            store.save(ItemTrackChoice(itemID: "m\(number)", mediaSourceID: nil, audioIndex: number))
        }

        #expect(store.itemChoice(for: "m0") == nil)
        #expect(store.itemChoice(for: "m1")?.audioIndex == 1)
        #expect(store.itemChoice(for: "m\(TrackChoiceStore.itemLimit)") != nil)
    }

    @Test func `forgetting removes everything for the user`() {
        let store = TrackChoiceStore(userID: "u1", defaults: defaults)
        store.save(ItemTrackChoice(itemID: "m1", mediaSourceID: nil, audioIndex: 1))
        store.save(SeriesTrackChoice(parentID: "show", parent: .series, kind: .audio, language: "jpn"))

        store.removeAll()

        #expect(store.itemChoice(for: "m1") == nil)
        #expect(store.seriesChoices(.audio, seriesID: "show", seasonID: nil).isEmpty)
    }
}
