import AnemoneCore
import Foundation
import Testing

/// Ported from Wholphin's `TestHomeRowSamples`, plus the JSON Wholphin writes.
struct HomeRowConfigTests {
    /// One of every kind, as in Wholphin's `SAMPLES`.
    static let samples: [HomeRowConfig] = {
        var thumbs = HomeRowViewOptions()
        thumbs.heightDp = 100
        thumbs.spacing = 8
        thumbs.contentScale = .crop
        thumbs.aspectRatio = .fourThree
        thumbs.imageType = .thumb
        thumbs.useSeries = false
        var filter = HomeGetItemsFilter()
        filter.parentID = "1dd1c2fd2e1b48e4ba9417a2350fe9cf"
        filter.recursive = true
        filter.isFavorite = true
        filter.includeItemTypes = ["Episode"]
        filter.sortBy = ["DateCreated"]
        filter.sortOrder = ["Descending"]
        return [
            HomeRowConfig(.recentlyAdded(parentID: "a1"), viewOptions: thumbs),
            HomeRowConfig(.recentlyReleased(parentID: "a2")),
            HomeRowConfig(.genres(parentID: "a3")),
            HomeRowConfig(.studios(parentID: "a4")),
            HomeRowConfig(.continueWatching),
            HomeRowConfig(.nextUp),
            HomeRowConfig(.continueWatchingCombined),
            HomeRowConfig(.byParent(parentID: "a5", recursive: true, sort: HomeRowSort(field: "CriticRating"))),
            HomeRowConfig(.getItems(name: "Episodes by date created", filter: filter)),
            HomeRowConfig(.favorite(itemKind: "Series")),
            HomeRowConfig(.recordings),
            HomeRowConfig(.tvPrograms),
            HomeRowConfig(.tvChannels),
            HomeRowConfig(.suggestions(parentID: "a6")),
            HomeRowConfig(.customEndpoint(HomeCustomEndpoint(
                endpoint: "/path/to/items",
                title: "Items",
                headers: [KeyValueEntry(key: "X-Header", value: "1234")],
                query: [KeyValueEntry(key: "key", value: "value")],
            ))),
        ]
    }()

    @Test func `every kind survives a round trip`() throws {
        let settings = HomePageSettings(rows: Self.samples)
        let decoded = try HomePageSettings(json: settings.json())
        #expect(decoded == settings)
    }

    @Test func `reads the JSON Wholphin writes, which leaves out defaults`() throws {
        let json = """
        {"rows":[
          {"type":"ContinueWatchingCombined"},
          {"type":"RecentlyAdded","parentId":"f137a2dd-21bb-c1b9-9aa5-c0f6bf02a805",
           "viewOptions":{"aspectRatio":"SQUARE","heightDp":128}},
          {"type":"Genres","parentId":"f137a2dd21bbc1b99aa5c0f6bf02a805"},
          {"type":"TvChannels"},
          {"type":"Favorite","kind":"Movie"},
          {"type":"ByParent","parentId":"10d10c62-d7f9-7b6b-33fe-2f3e4c11b69a",
           "sort":{"sort":"Random","direction":"Descending"}},
          {"type":"CustomEndpoint","endpoint":"/HomeScreen/Section","title":"Picks",
           "query":[{"key":"Section","value":"Latest"}]},
        ],"version":1}
        """

        let rows = try HomePageSettings(json: json).rows

        #expect(rows[0] == HomeRowConfig(.continueWatchingCombined))
        #expect(rows[1].kind == .recentlyAdded(parentID: "f137a2dd21bbc1b99aa5c0f6bf02a805"))
        #expect(rows[1].viewOptions.aspectRatio == .square)
        #expect(rows[1].viewOptions.heightDp == 128)
        // Fields left out take the plain defaults, not the kind's.
        #expect(rows[1].viewOptions.showTitles == false)
        #expect(rows[2].viewOptions == .genreDefault)
        #expect(rows[3].viewOptions == .liveTVDefault)
        #expect(rows[4].kind == .favorite(itemKind: "Movie"))
        #expect(rows[5].kind == .byParent(
            parentID: "10d10c62d7f97b6b33fe2f3e4c11b69a",
            recursive: false,
            sort: HomeRowSort(field: "Random", direction: .descending),
        ))
        #expect(rows[6].kind == .customEndpoint(HomeCustomEndpoint(
            endpoint: "/HomeScreen/Section",
            title: "Picks",
            query: [KeyValueEntry(key: "Section", value: "Latest")],
        )))
    }

    @Test func `skips rows of an unknown type, as Wholphin's parser does`() throws {
        let json = """
        {"type":"HomePageSettings","version":1,"rows":[
          {"type":"RecentlyAdded","parentId":"1dd1c2fd-2e1b-48e4-ba94-17a2350fe9cf"},
          {"type":"Does not exist","viewOptions":{}},
          {"type":"Genres"}
        ]}
        """

        let rows = try HomePageSettings(json: json).rows

        #expect(rows == [HomeRowConfig(.recentlyAdded(parentID: "1dd1c2fd2e1b48e4ba9417a2350fe9cf"))])
    }

    @Test func `an unknown enum value falls back to its default`() throws {
        let json = #"{"version":1,"rows":[{"type":"NextUp","viewOptions":{"imageType":"BANNER"}}]}"#

        let rows = try HomePageSettings(json: json).rows

        #expect(rows.first?.viewOptions.imageType == .primary)
    }

    @Test func `refuses a newer version or none`() {
        #expect(throws: HomeSettingsError.unsupportedVersion(2)) {
            try HomePageSettings(json: #"{"version":2,"rows":[]}"#)
        }
        #expect(throws: HomeSettingsError.unsupportedVersion(nil)) {
            try HomePageSettings(json: #"{"rows":[]}"#)
        }
    }

    @Test func `writes IDs dashed and fields under Wholphin's names`() throws {
        var options = HomeRowViewOptions()
        options.contentScale = .fillWidth
        let settings = HomePageSettings(rows: [
            HomeRowConfig(.genres(parentID: "f137a2dd21bbc1b99aa5c0f6bf02a805"), viewOptions: options),
        ])

        let json = try settings.json()

        #expect(json.contains(#""parentId":"f137a2dd-21bb-c1b9-9aa5-c0f6bf02a805""#))
        #expect(json.contains(#""type":"Genres""#))
        #expect(json.contains(#""contentScale":"Fill_WIDTH""#))
        #expect(json.contains(#""version":1"#))
    }

    @Test func `normalizes Jellyfin IDs`() {
        #expect(JellyfinID.compact("1DD1C2FD-2E1B-48E4-BA94-17A2350FE9CF") == "1dd1c2fd2e1b48e4ba9417a2350fe9cf")
        #expect(JellyfinID.dashed("1dd1c2fd2e1b48e4ba9417a2350fe9cf") == "1dd1c2fd-2e1b-48e4-ba94-17a2350fe9cf")
        #expect(JellyfinID.dashed("not-an-id") == "not-an-id")
    }
}
