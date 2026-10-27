import AnemoneJellyfin
import Foundation
import Synchronization
import Testing

/// Wholphin's other library tabs: Collections, Genres and Studios, the pages they open, the
/// remembered tab, and paging with the remote.
struct LibraryTabsTests {
    private let movies = Library(id: "lib-movies", name: "Movies", kind: .movies)
    private let shows = Library(id: "lib-shows", name: "Shows", kind: .shows)
    private let music = Library(id: "lib-music", name: "Music", kind: .music)

    // MARK: Tabs

    @Test func `movie and TV libraries get Wholphin's tabs, others only their grid`() {
        #expect(movies.sections == [.recommended, .library, .collections, .genres])
        #expect(shows.sections == [.recommended, .library, .genres, .studios])
        #expect(music.sections == [.library])
        #expect(Library(id: "h", name: "Home videos", kind: .homeVideos).sections == [.library])
    }

    @Test func `opens on the remembered tab when the library still has it`() {
        #expect(movies.startingSection(remembered: "genres") == .genres)
        #expect(movies.startingSection(remembered: nil) == .recommended)
        // Movie libraries have no Studios tab, and nothing else matches an unknown name.
        #expect(movies.startingSection(remembered: "studios") == .recommended)
        #expect(shows.startingSection(remembered: "nonsense") == .recommended)
        #expect(music.startingSection(remembered: "genres") == .library)
    }

    // MARK: Grids behind the tabs

    @Test func `the Collections tab lists box sets from anywhere in the library`() async throws {
        let sent = recordRequests(host: "collections.test")

        let page = try await librarySession(host: "collections.test")
            .libraryItems(LibraryQuery(library: movies, scope: .collections), startIndex: 0, limit: 50)

        let query = try #require(sent.withLock { $0.first }?.query)
        #expect(query["parentId"] == ["lib-movies"])
        #expect(query["includeItemTypes"] == ["BoxSet"])
        #expect(query["recursive"] == ["true"])
        // Still sorted the way the library's own grid is.
        #expect(query["sortBy"] == ["SortName", "ProductionYear"])
        #expect(page.items.map(\.item.name) == ["Item 0", "Item 1"])
    }

    @Test func `a genre's and a studio's pages narrow the library's titles to it`() async throws {
        let sent = recordRequests(host: "genre-page.test")
        var filter = LibraryFilter()
        filter.played = false

        _ = try await librarySession(host: "genre-page.test")
            .libraryItems(LibraryQuery(library: movies, filter: filter, scope: .genre("g1")), startIndex: 0, limit: 1)
        _ = try await librarySession(host: "genre-page.test")
            .libraryItems(LibraryQuery(library: shows, scope: .studio("s1")), startIndex: 0, limit: 1)

        let queries = sent.withLock { $0.map(\.query) }
        #expect(queries[0]["genreIds"] == ["g1"])
        #expect(queries[0]["includeItemTypes"] == ["Movie"])
        #expect(queries[0]["recursive"] == ["true"])
        #expect(queries[0]["isPlayed"] == ["false"])
        #expect(queries[1]["studioIds"] == ["s1"])
        #expect(queries[1]["includeItemTypes"] == ["Series"])
        #expect(queries[1]["genreIds"] == nil)
    }

    @Test func `the alphabet bar counts within the tab's own items`() async throws {
        let sent = recordRequests(host: "genre-jump.test", total: 12)

        let position = try await librarySession(host: "genre-jump.test")
            .position(of: "D", in: LibraryQuery(library: movies, scope: .genre("g1")), count: 30)

        #expect(position == 12)
        let query = try #require(sent.withLock { $0.first }?.query)
        #expect(query["genreIds"] == ["g1"])
        #expect(query["nameLessThan"] == ["d"])
    }

    @Test func `entries carry what the list layout and details header show`() async throws {
        MockServer.register(host: "entry.test") { _ in
            .json(#"""
            {"Items":[{"Id":"s1","Name":"Pioneer One","SortName":"pioneer one","Type":"Series",
              "ProductionYear":2010,"Overview":"A capsule falls.","CommunityRating":7.5,
              "ImageTags":{"Primary":"p1","Logo":"l1"},
              "UserData":{"Key":"s1","Played":false,"IsFavorite":true,"UnplayedItemCount":3}}],
             "TotalRecordCount":1}
            """#)
        }

        let page = try await librarySession(host: "entry.test")
            .libraryItems(LibraryQuery(library: shows), startIndex: 0, limit: 1, includeTotalCount: true)

        let entry = try #require(page.items.first)
        let details = try #require(entry.details)
        #expect(entry.item.overview == "A capsule falls.")
        #expect(details.userState.isFavorite)
        #expect(!details.userState.isPlayed)
        #expect(details.userState.unplayedCount == 3)
        #expect(details.communityRating == 7.5)
        #expect(details.logo == ItemImage(itemID: "s1", kind: .logo, tag: "l1"))
    }

    // MARK: Paging with the remote

    @Test func `page buttons move six rows, more in big libraries, and stop at the ends`() {
        #expect(LibraryJump.page(from: 3, forward: true, columns: 6, count: 500) == 39)
        #expect(LibraryJump.page(from: 39, forward: false, columns: 6, count: 500) == 3)
        #expect(LibraryJump.page(from: 10, forward: false, columns: 6, count: 500) == 0)
        #expect(LibraryJump.page(from: 490, forward: true, columns: 6, count: 500) == 499)
        #expect(LibraryJump.page(from: 0, forward: true, columns: 6, count: 3000) == 90)
        #expect(LibraryJump.page(from: 0, forward: true, columns: 4, count: 10000) == 200)
        #expect(LibraryJump.page(from: 0, forward: true, columns: 6, count: 30000) == 3000)
        #expect(LibraryJump.page(from: 0, forward: true, columns: 1, count: 50) == 6)
        #expect(LibraryJump.page(from: 0, forward: true, columns: 6, count: 0) == 0)
    }

    @Test func `letters jump within a list that's all loaded`() {
        let names: [String?] = ["1917", "action", "comedy", "drama", "Western", nil]

        #expect(LibraryJump.position(of: "#", in: names) == 0)
        #expect(LibraryJump.position(of: "A", in: names) == 1)
        #expect(LibraryJump.position(of: "B", in: names) == 2)
        #expect(LibraryJump.position(of: "W", in: names) == 4)
        #expect(LibraryJump.position(of: "Z", in: names) == 6)
    }

    // MARK: Genres and studios

    @Test func `lists a library's genres and studios with their images`() async throws {
        let sent = recordCategoryRequests(host: "categories.test")
        let session = try librarySession(host: "categories.test")

        let genres = try await session.libraryGenres(in: movies)
        let studios = try await session.libraryStudios(in: shows)

        #expect(genres.map(\.item.name) == ["Action", "Drama"])
        #expect(genres.map(\.sortName) == ["action", "drama"])
        #expect(studios.map(\.item.name) == ["AMC", "HBO"])
        #expect(studios[0].item.thumbImage == ItemImage(itemID: "st1", kind: .thumb, tag: "t1"))
        #expect(studios[1].item.thumbImage == nil)
        let queries = sent.withLock { $0 }
        let genreQuery = try #require(queries.first { $0.path == "/Genres" }?.query)
        #expect(genreQuery["parentId"] == ["lib-movies"])
        #expect(genreQuery["includeItemTypes"] == ["Movie"])
        #expect(genreQuery["sortBy"] == ["SortName"])
        let studioQuery = try #require(queries.first { $0.path == "/Studios" }?.query)
        #expect(studioQuery["parentId"] == ["lib-shows"])
        #expect(studioQuery["includeItemTypes"] == ["Series"])
    }

    @Test func `a genre card shows the backdrop of a random title in it`() async throws {
        let sent = recordCategoryRequests(host: "genre-art.test")

        let backdrops = try await librarySession(host: "genre-art.test")
            .genreBackdrops(for: ["g1", "g2", "g3", "g4", "g5", "g6"], in: movies)

        // g2 has no title with a backdrop, and g6's request fails, so the set isn't kept.
        let images = backdrops.images
        #expect(!backdrops.isComplete)
        #expect(images.count == 4)
        #expect(images["g1"] == ItemImage(itemID: "in-g1", kind: .backdrop, tag: "b-g1"))
        #expect(images["g2"] == nil)
        #expect(images["g6"] == nil)
        let queries = sent.withLock { $0.filter { $0.path == "/Items" }.map(\.query) }
        #expect(queries.count == 6)
        let first = try #require(queries.first { $0["genreIds"] == ["g1"] })
        #expect(first["sortBy"] == ["Random"])
        #expect(first["limit"] == ["1"])
        #expect(first["imageTypes"] == ["Backdrop"])
        #expect(first["includeItemTypes"] == ["Movie"])
        #expect(first["recursive"] == ["true"])
    }

    @Test func `genre art is complete when every genre was answered, even with no picture`() async throws {
        _ = recordCategoryRequests(host: "genre-art-all.test")

        let backdrops = try await librarySession(host: "genre-art-all.test")
            .genreBackdrops(for: ["g1", "g2", "g3", "g4", "g5"], in: movies)

        #expect(backdrops.isComplete)
        #expect(backdrops.images.keys.sorted() == ["g1", "g3", "g4", "g5"])
    }

    @Test func `genre art cut short by leaving the tab is incomplete and asks for no more`() async throws {
        let sent = recordCategoryRequests(host: "genre-art-left.test")
        let session = try librarySession(host: "genre-art-left.test")
        let library = movies

        // The tab's task is cancelled when another tab is chosen.
        let backdrops = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await session.genreBackdrops(for: ["g1", "g3", "g4", "g5", "g7"], in: library)
        }.value

        #expect(!backdrops.isComplete)
        #expect(sent.withLock { $0.isEmpty })
    }

    // MARK: Helpers

    /// Answers `/Items` with two items and `total` as the count, recording each request.
    private func recordRequests(host: String, total: Int = 2) -> RequestLog {
        let sent = RequestLog()
        MockServer.register(host: host) { request in
            sent.withLock { $0.append(SeenRequest(request)) }
            return .json(#"""
            {"Items":[
              {"Id":"i0","Name":"Item 0","SortName":"item 0","Type":"BoxSet"},
              {"Id":"i1","Name":"Item 1","SortName":"item 1","Type":"BoxSet"}
            ],"TotalRecordCount":\#(total)}
            """#)
        }
        return sent
    }

    /// Answers `/Genres`, `/Studios`, and `/Items` for one genre's random title: `g2` has none,
    /// and `g6` fails.
    private func recordCategoryRequests(host: String) -> RequestLog {
        let sent = RequestLog()
        MockServer.register(host: host) { request in
            let seen = SeenRequest(request)
            sent.withLock { $0.append(seen) }
            switch seen.path {
            case "/Genres":
                return .json(#"""
                {"Items":[{"Id":"g1","Name":"Action","SortName":"action","Type":"Genre"},
                          {"Id":"g2","Name":"Drama","SortName":"drama","Type":"Genre"}]}
                """#)
            case "/Studios":
                return .json(#"""
                {"Items":[{"Id":"st1","Name":"AMC","SortName":"amc","Type":"Studio","ImageTags":{"Thumb":"t1"}},
                          {"Id":"st2","Name":"HBO","SortName":"hbo","Type":"Studio"}]}
                """#)
            case "/Items":
                let genre = seen.query["genreIds"]?.first ?? ""
                switch genre {
                case "g2": return .json(#"{"Items":[]}"#)
                case "g6": return nil
                default: return .json(#"{"Items":[{"Id":"in-\#(genre)","BackdropImageTags":["b-\#(genre)"]}]}"#)
                }
            default:
                return nil
            }
        }
        return sent
    }
}
