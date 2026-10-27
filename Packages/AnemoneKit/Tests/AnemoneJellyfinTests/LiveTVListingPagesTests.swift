@testable import AnemoneJellyfin
import Testing

/// The guide's listing loads: pages asked for once, reloads after a recording changed, and only
/// the newest answer for a page going up, however the answers land.
struct LiveTVListingPagesTests {
    /// Pages of 20 channels, with the first page up, as after the guide's first load.
    private static func loaded() -> LiveTVListingPages {
        var pages = LiveTVListingPages(pageSize: 20)
        let first = pages.start(0)
        let again = pages.startOver(showing: first)
        #expect(again.isEmpty)
        return pages
    }

    /// Whether each answer goes up, landing in the order given.
    private static func land(_ loads: [LiveTVListingPages.Load], on pages: inout LiveTVListingPages) -> [Bool] {
        loads.map { pages.accept($0) }
    }

    /// The first load of the row's page, which must be its first.
    private static func firstLoad(
        forRow index: Int,
        in pages: inout LiveTVListingPages,
    ) throws -> LiveTVListingPages.Load {
        let load = pages.firstLoad(forRow: index)
        return try #require(load)
    }

    /// The reload of `page` after a recording on the channel at `channelIndex` changed.
    private static func reload(
        page: Int,
        channelIndex: Int?,
        in pages: inout LiveTVListingPages,
    ) throws -> LiveTVListingPages.Load {
        let loads = pages.reloads(channelIndex: channelIndex)
        return try #require(loads.first { $0.page == page })
    }

    @Test func `a page is asked for once, by the first of its rows to show`() {
        var pages = Self.loaded()

        let onFirstPage = pages.firstLoad(forRow: 3)
        let second = pages.firstLoad(forRow: 20)
        let onSecondPage = pages.firstLoad(forRow: 39)

        #expect(onFirstPage == nil)
        #expect(second?.page == 1)
        #expect(onSecondPage == nil)
        #expect(pages.requested == [0, 1])
    }

    @Test func `a reload landing before a row's first load keeps the reload's answer`() throws {
        var pages = Self.loaded()
        let first = try Self.firstLoad(forRow: 25, in: &pages)
        let reload = try Self.reload(page: 1, channelIndex: nil, in: &pages)

        // The first load asked before the recording changed, so its markers are stale.
        #expect(Self.land([reload, first], on: &pages) == [true, false])
    }

    @Test func `answers landing in order both go up`() throws {
        var pages = Self.loaded()
        let first = try Self.firstLoad(forRow: 25, in: &pages)
        let reload = try Self.reload(page: 1, channelIndex: nil, in: &pages)

        #expect(Self.land([first, reload], on: &pages) == [true, true])
    }

    @Test func `of two quick reloads, the second's answer stays up whichever lands last`() throws {
        var pages = Self.loaded()
        let recorded = try Self.reload(page: 0, channelIndex: 4, in: &pages)
        let cancelled = try Self.reload(page: 0, channelIndex: 4, in: &pages)
        // Other pages aren't held back by this one's.
        let other = try Self.firstLoad(forRow: 40, in: &pages)

        #expect(Self.land([cancelled, recorded, other], on: &pages) == [true, false, true])
    }

    @Test func `a programme's recording reloads only its channel's page, a series every page`() throws {
        var pages = Self.loaded()
        _ = try Self.firstLoad(forRow: 20, in: &pages)
        _ = try Self.firstLoad(forRow: 45, in: &pages)

        let programOnSecondPage = pages.reloads(channelIndex: 27).map(\.page)
        let programOnFirstPage = pages.reloads(channelIndex: 0).map(\.page)
        let series = pages.reloads(channelIndex: nil).map(\.page)
        let programOnPageNotShown = pages.reloads(channelIndex: 70)

        #expect(programOnSecondPage == [1])
        #expect(programOnFirstPage == [0])
        #expect(series == [0, 1, 2])
        // A page no row has asked for loads when its rows show.
        #expect(programOnPageNotShown.isEmpty)
    }

    @Test func `a new guide makes earlier loads stale and asks again for the pages shown`() throws {
        var pages = Self.loaded()
        let second = try Self.firstLoad(forRow: 20, in: &pages)
        let reload = try Self.reload(page: 0, channelIndex: 0, in: &pages)
        let firstOfNewGuide = pages.start(0)

        let again = pages.startOver(showing: firstOfNewGuide)

        #expect(again.map(\.page) == [1])
        #expect(pages.requested == [0, 1])
        #expect(Self.land([second, reload] + again, on: &pages) == [false, false, true])
    }

    @Test func `a reload asked for while a new guide loaded asks again under the new guide`() throws {
        var pages = Self.loaded()
        let firstOfNewGuide = pages.start(0)
        // A recording changed while the new guide loaded: its reload is stale once the guide is up,
        // but its markers are newer than the guide's.
        let reload = try Self.reload(page: 0, channelIndex: 0, in: &pages)

        let again = pages.startOver(showing: firstOfNewGuide)

        #expect(again.map(\.page) == [0])
        #expect(Self.land([reload] + again, on: &pages) == [false, true])
    }

    @Test func `a page whose first load failed is asked for again; one showing listings keeps them`() throws {
        var pages = Self.loaded()
        let failed = try Self.firstLoad(forRow: 20, in: &pages)

        pages.failed(failed)
        let retry = pages.firstLoad(forRow: 20)

        #expect(retry?.page == 1)

        let reload = try Self.reload(page: 0, channelIndex: 0, in: &pages)
        pages.failed(reload)
        #expect(pages.requested.contains(0))
    }
}
