import AnemoneJellyfin
import Foundation
import Testing

/// A library's Recommended tab: Wholphin's rows and its suggestions.
struct LibraryRecommendedTests {
    private let movies = Library(id: "lib-movies", name: "Movies", kind: .movies)
    private let shows = Library(id: "lib-shows", name: "Shows", kind: .shows)

    // MARK: Recommended

    @Test func `a refresh asks only for the rows it's given, and merging keeps the others`() async throws {
        let sent = recordRecommendedRequests(host: "rec-refresh.test")

        let fresh = try await librarySession(host: "rec-refresh.test").recommended(
            in: movies,
            rows: [.continueWatching, .recentlyReleased, .recentlyAdded, .topUnwatched],
            itemsPerRow: 10,
            now: Date(timeIntervalSince1970: 1_800_000_000),
        )

        #expect(fresh.rows.map(\.kind) == [.continueWatching, .recentlyReleased, .recentlyAdded])
        // Suggestions ask for the last played titles' genres; nothing asked for them.
        #expect(!sent.requests.contains { $0.query["sortBy"] == "DatePlayed" })

        let suggestions = RecommendedRow(kind: .suggestions, items: [MediaItem(id: "s1", name: "Kept", kind: .movie)])
        let shown = RecommendedContent(
            rows: [RecommendedRow(kind: .continueWatching, items: [MediaItem(id: "old", name: "Old", kind: .movie)]), suggestions],
            failedRows: [.topUnwatched],
        )
        let merged = shown.merging(fresh, keeping: [.suggestions], order: movies.recommendedRows)
        #expect(merged.rows.map(\.kind) == [.continueWatching, .recentlyReleased, .recentlyAdded, .suggestions])
        #expect(merged.rows[0].items.map(\.id) == ["resume-1"])
        #expect(merged.rows.last?.items.map(\.id) == ["s1"])
        #expect(merged.failedRows.isEmpty)
    }

    @Test func `a movie library recommends Wholphin's rows in order, leaving out empty ones`() async throws {
        let sent = recordRecommendedRequests(host: "rec-movies.test")
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let content = try await librarySession(host: "rec-movies.test").recommended(
            in: movies,
            itemsPerRow: 10,
            now: now,
        )

        // Top Unwatched comes back empty here, so it's left out.
        #expect(content.rows.map(\.kind) == [.continueWatching, .recentlyReleased, .recentlyAdded, .suggestions])
        #expect(content.failedRows.isEmpty)
        #expect(content.rows[0].items.map(\.id) == ["resume-1"])
        let queries = sent.requests
        let resume = try #require(queries.first { $0.path == "/UserItems/Resume" }?.query)
        #expect(resume["parentId"] == "lib-movies")
        #expect(resume["includeItemTypes"] == "Movie")
        #expect(resume["limit"] == "10")
        #expect(!queries.contains { $0.path == "/Shows/NextUp" })
        let released = try #require(queries.first { $0.query["sortBy"] == "PremiereDate,SortName" }?.query)
        #expect(released["sortOrder"] == "Descending,Ascending")
        #expect(released["maxPremiereDate"] != nil)
        #expect(released["includeItemTypes"] == "Movie")
        #expect(released["recursive"] == "true")
        let added = try #require(queries.first { $0.query["sortBy"] == "DateCreated" && $0.query["limit"] == "10" })
        #expect(added.query["sortOrder"] == "Descending")
        let unwatched = try #require(queries.first { $0.query["sortBy"] == "CommunityRating" }?.query)
        #expect(unwatched["isPlayed"] == "false")
        #expect(unwatched["includeItemTypes"] == "Movie")
    }

    @Test func `a TV library recommends episodes, Next Up and unwatched series`() async throws {
        let sent = recordRecommendedRequests(host: "rec-shows.test")

        let content = try await librarySession(host: "rec-shows.test").recommended(in: shows, itemsPerRow: 10)

        #expect(content.rows.map(\.kind).first == .continueWatching)
        #expect(content.rows.map(\.kind).contains(.nextUp))
        let queries = sent.requests
        let resume = try #require(queries.first { $0.path == "/UserItems/Resume" }?.query)
        #expect(resume["includeItemTypes"] == "Episode")
        let nextUp = try #require(queries.first { $0.path == "/Shows/NextUp" }?.query)
        #expect(nextUp["parentId"] == "lib-shows")
        #expect(nextUp["enableResumable"] == "false")
        #expect(nextUp["enableRewatching"] == "false")
        let released = try #require(queries.first { $0.query["sortBy"]?.hasPrefix("PremiereDate,") == true }?.query)
        #expect(released["sortBy"] == "PremiereDate,SeriesSortName,AiredEpisodeOrder")
        #expect(released["sortOrder"] == "Descending,Ascending,Descending")
        #expect(released["isUnaired"] == "false")
        #expect(released["includeItemTypes"] == "Episode")
        let unwatched = try #require(queries.first { $0.query["sortBy"] == "CommunityRating" }?.query)
        #expect(unwatched["includeItemTypes"] == "Series")
    }

    @Test func `the tab follows Home's items per row and Next Up rewatching settings`() async throws {
        let sent = recordRecommendedRequests(host: "rec-settings.test")

        _ = try await librarySession(host: "rec-settings.test").recommended(
            in: shows,
            itemsPerRow: 5,
            enableRewatchingNextUp: true,
        )

        let queries = sent.requests
        let nextUp = try #require(queries.first { $0.path == "/Shows/NextUp" }?.query)
        #expect(nextUp["enableRewatching"] == "true")
        #expect(nextUp["limit"] == "5")
        #expect(queries.first { $0.path == "/UserItems/Resume" }?.query["limit"] == "5")
        let items = queries.filter { $0.path == "/Items" }.map(\.query)
        let released = try #require(items.first { $0["sortBy"]?.hasPrefix("PremiereDate,") == true })
        let added = try #require(items.first { $0["sortBy"] == "DateCreated" && $0["isPlayed"] == nil })
        let unwatched = try #require(items.first { $0["sortBy"] == "CommunityRating" })
        #expect([released, added, unwatched].allSatisfy { $0["limit"] == "5" })
        // The suggestions are cut from five too: 30% new and 30% random, at least one of each.
        let newest = try #require(items.first { $0["sortBy"] == "DateCreated" && $0["isPlayed"] == "false" })
        #expect(newest["limit"] == "1")
    }

    @Test func `a failing row is left out and reported, but a revoked token stops the tab`() async throws {
        MockServer.register(host: "rec-fail.test") { request in
            request.url?.path() == "/UserItems/Resume" ? nil : .json(#"{"Items":[]}"#)
        }
        MockServer.register(host: "rec-401.test") { request in
            request.url?.path() == "/UserItems/Resume" ? .unauthorized : .json(#"{"Items":[]}"#)
        }

        let content = try await librarySession(host: "rec-fail.test").recommended(in: movies)

        #expect(content.rows.isEmpty)
        #expect(content.failedRows == [.continueWatching])
        await #expect(throws: SessionError.signedOut) {
            try await librarySession(host: "rec-401.test").recommended(in: movies)
        }
    }

    @Test func `suggests titles like the last three watched, plus new and random ones`() async throws {
        let sent = recordSuggestionRequests(host: "suggest.test")

        let items = try await librarySession(host: "suggest.test").suggestions(in: movies, limit: 25) { $0 }

        // Watched titles and repeats are left out; the mix keeps its order when not shuffled.
        #expect(items.map(\.id) == ["m5", "m6", "m7", "m8"])
        let queries = sent.requests.map(\.query)
        let history = try #require(queries.first { $0["isPlayed"] == "true" })
        #expect(history["includeItemTypes"] == "Movie")
        #expect(history["sortBy"] == "DatePlayed")
        #expect(history["sortOrder"] == "Descending")
        #expect(history["fields"] == "Genres")
        #expect(history["limit"] == "20")
        let alike = try #require(queries.first { $0["genreIds"] != nil })
        #expect(alike["genreIds"] == "g1,g2,g3")
        #expect(alike["excludeItemIds"] == "m1,m2,m3")
        #expect(alike["isPlayed"] == "false")
        #expect(alike["sortBy"] == "Random")
        #expect(alike["limit"] == "10")
        let fresh = try #require(queries.first { $0["sortBy"] == "DateCreated" })
        #expect(fresh["sortOrder"] == "Descending")
        #expect(fresh["limit"] == "7")
        #expect(fresh["genreIds"] == nil)
        let random = try #require(queries.first { $0["sortBy"] == "Random" && $0["genreIds"] == nil })
        #expect(random["limit"] == "7")
    }

    @Test func `suggestions for TV start from watched episodes' series`() async throws {
        let sent = Recorder()
        MockServer.register(host: "suggest-tv.test") { request in
            if sent.record(request).query["isPlayed"] == "true" {
                return .json(#"""
                {"Items":[{"Id":"e1","SeriesId":"s1","Type":"Episode","GenreItems":[{"Id":"g1"}]},
                          {"Id":"e2","SeriesId":"s1","Type":"Episode"}]}
                """#)
            }
            return .json(
                #"{"Items":[{"Id":"s1","Name":"Seen","Type":"Series"},{"Id":"s2","Name":"New","Type":"Series"}]}"#,
            )
        }

        let items = try await librarySession(host: "suggest-tv.test").suggestions(in: shows, limit: 10) { $0 }

        #expect(items.map(\.id) == ["s2"])
        let queries = sent.requests.map(\.query)
        #expect(queries.first { $0["isPlayed"] == "true" }?["includeItemTypes"] == "Episode")
        let alike = try #require(queries.first { $0["genreIds"] != nil })
        #expect(alike["excludeItemIds"] == "s1")
        #expect(alike["includeItemTypes"] == "Series")
    }

    @Test func `with nothing watched, suggestions are only new and random titles`() async throws {
        let sent = Recorder()
        MockServer.register(host: "suggest-new.test") { request in
            sent.record(request)
            return .json(#"{"Items":[]}"#)
        }

        let items = try await librarySession(host: "suggest-new.test").suggestions(in: movies)

        #expect(items.isEmpty)
        #expect(sent.requests.count == 3)
        #expect(!sent.requests.contains { $0.query["genreIds"] != nil })
    }

    // MARK: Helpers

    /// Answers each Recommended row with one item named for it; Top Unwatched comes back empty.
    private func recordRecommendedRequests(host: String) -> Recorder {
        let sent = Recorder()
        MockServer.register(host: host) { request in
            let seen = sent.record(request)
            let firstSort = seen.query["sortBy"]?.components(separatedBy: ",").first
            let id = switch (seen.path, firstSort, seen.query["isPlayed"]) {
            case ("/UserItems/Resume", _, _): "resume-1"
            case ("/Shows/NextUp", _, _): "next-1"
            case (_, "PremiereDate", _): "released-1"
            case (_, "DateCreated", _): "added-1"
            case (_, "CommunityRating", _): ""
            case (_, _, "true"): ""
            default: "suggested-1"
            }
            return .json(id.isEmpty ? #"{"Items":[]}"# : #"{"Items":[{"Id":"\#(id)","Name":"\#(id)","Type":"Movie"}]}"#)
        }
        return sent
    }

    /// Answers the suggestion requests: the history (m1 twice, m2, m3, m4), titles alike
    /// (with watched m1), new ones (m6 again) and random ones (with watched m2).
    private func recordSuggestionRequests(host: String) -> Recorder {
        let sent = Recorder()
        MockServer.register(host: host) { request in
            let seen = sent.record(request)
            if seen.query["isPlayed"] == "true" {
                return .json(#"""
                {"Items":[
                  {"Id":"m1","Type":"Movie","GenreItems":[{"Id":"g1"},{"Id":"g2"}]},
                  {"Id":"m1","Type":"Movie","GenreItems":[{"Id":"g1"}]},
                  {"Id":"m2","Type":"Movie","GenreItems":[{"Id":"g2"},{"Id":"g3"}]},
                  {"Id":"m3","Type":"Movie"},
                  {"Id":"m4","Type":"Movie","GenreItems":[{"Id":"g9"}]}
                ]}
                """#)
            }
            let ids: [String] = if seen.query["genreIds"] != nil {
                ["m5", "m1", "m6"]
            } else if seen.query["sortBy"] == "DateCreated" {
                ["m6", "m7"]
            } else {
                ["m8", "m2"]
            }
            let items = ids.map { #"{"Id":"\#($0)","Name":"\#($0)","Type":"Movie"}"# }.joined(separator: ",")
            return .json(#"{"Items":[\#(items)]}"#)
        }
        return sent
    }
}
