#if ANEMONE_SEERR
    @testable import AnemoneSeerr
    import Foundation
    import Testing

    struct SeerrRequestTests {
        /// A series with three seasons: the first on the server, the second asked for by the user
        /// (id 7) and still pending, the third not asked for.
        private static let series = #"""
        {"id":1399,"name":"Thrones","firstAirDate":"2011-04-17","tagline":"","episodeRunTime":[60],
         "genres":[{"id":1,"name":"Drama"}],"voteAverage":8.4,
         "seasons":[{"id":1,"seasonNumber":1,"name":"Season 1","episodeCount":10},
                    {"id":2,"seasonNumber":2,"name":"Season 2","episodeCount":10},
                    {"id":3,"seasonNumber":3,"name":"Season 3","episodeCount":10}],
         "mediaInfo":{"status":4,"jellyfinMediaId":"9bd5926326d651153928e0d11c6ee7cb",
           "seasons":[{"seasonNumber":1,"status":5}],
           "requests":[{"id":42,"status":1,"is4k":false,"requestedBy":{"id":7},
                        "seasons":[{"seasonNumber":2,"status":1}]}]}}
        """#

        @Test func `a series shows each season's state and who may ask again`() async throws {
            let seerr = try await connection(to: "series.seerr.test") { request in
                request.path == "/api/v1/tv/1399" ? .json(Self.series) : nil
            }

            let details = try await seerr.series(1399)

            #expect(details.item.title == "Thrones")
            #expect(details.item.availability == .partiallyAvailable)
            #expect(details.item.jellyfinItemID == "9bd5926326d651153928e0d11c6ee7cb")
            #expect(details.tagline == nil)
            #expect(details.genres == ["Drama"])
            #expect(details.runtime == 60)
            #expect(details.seasons.map(\.availability) == [.available, .pending, .unknown])
            #expect(details.seasons.map(\.requestStatus) == [.unknown, .pending, .unknown])
            // The user's own pending request can be changed; season 1 is already there.
            #expect(details.seasons.map(\.isRequestable) == [false, true, true])
            #expect(details.seasons4K.map(\.availability) == [.unknown, .unknown, .unknown])
            #expect(details.requests == [SeerrRequest(
                id: 42,
                status: .pending,
                requestedBy: 7,
                seasons: [2: .pending],
            )])
        }

        @Test func `asking for more seasons changes the user's pending request`() async throws {
            let seerr = try await connection(to: "update.seerr.test") { request in
                switch (request.method, request.path) {
                case ("GET", "/api/v1/tv/1399"): .json(Self.series)
                case ("PUT", "/api/v1/request/42"): .json(#"{"id":42,"status":1}"#)
                default: nil
                }
            }
            let details = try await seerr.series(1399)

            try await seerr.requestSeries(details, seasons: [2, 3], is4K: false)

            let sent = try #require(SeerrMockServer.requests(to: "update.seerr.test").last)
            #expect(sent.method == "PUT")
            #expect(sent.json["mediaType"] as? String == "tv")
            #expect(sent.json["seasons"] as? [Int] == [2, 3])
            #expect(sent.json["is4k"] as? Bool == false)
        }

        /// A series with four seasons: the first on the server; the second and third in the
        /// user's (id 7) pending request, with another user's approved request for the second and
        /// a declined one for the third listed after it; the fourth not asked for. The user's
        /// request also has a fifth season TMDB doesn't list.
        private static let sharedSeasons = #"""
        {"id":1399,"name":"Thrones",
         "seasons":[{"seasonNumber":1},{"seasonNumber":2},{"seasonNumber":3},{"seasonNumber":4}],
         "mediaInfo":{"status":4,"seasons":[{"seasonNumber":1,"status":5}],
           "requests":[
             {"id":42,"status":1,"is4k":false,"requestedBy":{"id":7},
              "seasons":[{"seasonNumber":2,"status":1},{"seasonNumber":3,"status":1},
                         {"seasonNumber":5,"status":1}]},
             {"id":43,"status":2,"is4k":false,"requestedBy":{"id":8},"seasons":[{"seasonNumber":2,"status":2}]},
             {"id":44,"status":3,"is4k":false,"requestedBy":{"id":9},"seasons":[{"seasonNumber":3,"status":3}]}]}}
        """#

        @Test func `changing a request keeps the seasons the user didn't untick`() async throws {
            let host = "shared.seerr.test"
            let seerr = try await connection(to: host) { request in
                switch (request.method, request.path) {
                case ("GET", "/api/v1/tv/1399"): .json(Self.sharedSeasons)
                case ("PUT", "/api/v1/request/42"): .json(#"{"id":42,"status":1}"#)
                default: nil
                }
            }
            let details = try await seerr.series(1399)
            // The user's own seasons can still be changed, and start ticked, whatever else asks
            // for them.
            #expect(details.seasons.map(\.isRequestable) == [false, true, true, true])
            let ticked = details.seasons.filter(\.isInOwnRequest).map(\.number)
            #expect(ticked == [2, 3])

            try await seerr.requestSeries(details, seasons: ticked + [4], is4K: false)
            let added = try #require(SeerrMockServer.requests(to: host).last)
            #expect(added.method == "PUT")
            #expect(added.path == "/api/v1/request/42")
            // The fifth season wasn't offered, so it couldn't be unticked: it stays.
            #expect(added.json["seasons"] as? [Int] == [2, 3, 4, 5])

            try await seerr.requestSeries(details, seasons: [2], is4K: false)
            let unticked = try #require(SeerrMockServer.requests(to: host).last)
            #expect(unticked.json["seasons"] as? [Int] == [2, 5])
        }

        @Test func `asking for a series in 4K makes a new request`() async throws {
            let seerr = try await connection(to: "new4k.seerr.test") { request in
                switch (request.method, request.path) {
                case ("GET", "/api/v1/tv/1399"): .json(Self.series)
                case ("POST", "/api/v1/request"): SeerrMockServer.Reply(status: 201, body: #"{"id":43,"status":1}"#)
                default: nil
                }
            }
            let details = try await seerr.series(1399)

            try await seerr.requestSeries(details, seasons: [1], is4K: true)

            let sent = try #require(SeerrMockServer.requests(to: "new4k.seerr.test").last)
            #expect(sent.method == "POST")
            #expect(sent.json["mediaId"] as? Int == 1399)
            #expect(sent.json["seasons"] as? [Int] == [1])
            #expect(sent.json["is4k"] as? Bool == true)
        }

        @Test func `asking for a movie posts its TMDB ID`() async throws {
            let seerr = try await connection(to: "movie.seerr.test") { request in
                request.path == "/api/v1/request" ? SeerrMockServer
                    .Reply(status: 201, body: #"{"id":1,"status":1}"#) : nil
            }

            try await seerr.requestMovie(550, is4K: false)

            let sent = try #require(SeerrMockServer.requests(to: "movie.seerr.test").last)
            #expect(sent.method == "POST")
            #expect(sent.json["mediaType"] as? String == "movie")
            #expect(sent.json["mediaId"] as? Int == 550)
        }

        @Test func `a request Seerr refuses throws`() async throws {
            let seerr = try await connection(to: "refused.seerr.test") { request in
                request.path == "/api/v1/request" ? .status(403) : nil
            }

            await #expect(throws: SeerrError.forbidden) {
                try await seerr.requestMovie(550, is4K: false)
            }
        }

        @Test func `cancelling deletes the request`() async throws {
            let seerr = try await connection(to: "cancel.seerr.test") { request in
                request.method == "DELETE" ? SeerrMockServer.Reply(status: 204, body: "") : nil
            }

            try await seerr.cancelRequest(SeerrRequest(id: 42, status: .pending))

            let sent = try #require(SeerrMockServer.requests(to: "cancel.seerr.test").last)
            #expect(sent.method == "DELETE")
            #expect(sent.path == "/api/v1/request/42")
        }

        @Test func `a user may cancel their own unapproved request, a manager any`() async throws {
            let seerr = try await connection(to: "who.seerr.test") { _ in nil }
            let own = SeerrRequest(id: 1, status: .pending, requestedBy: 7)
            let others = SeerrRequest(id: 2, status: .pending, requestedBy: 8)
            let approved = SeerrRequest(id: 3, status: .approved, requestedBy: 7)
            func details(_ requests: [SeerrRequest]) -> DiscoverDetails {
                DiscoverDetails(item: DiscoverItem(tmdbID: 1, kind: .movie, title: "A"), requests: requests)
            }

            #expect(seerr.requestToCancel(in: details([others, own])) == own)
            #expect(seerr.requestToCancel(in: details([others])) == nil)
            #expect(seerr.requestToCancel(in: details([approved])) == nil)

            let manager = try await connection(to: "manager.seerr.test", permissions: 16) { _ in nil }
            #expect(manager.requestToCancel(in: details([others, own])) == others)
        }

        @Test func `a series Seerr doesn't know shows the user's own request`() {
            let pending = SeerrRequest(id: 1, status: .pending, requestedBy: 7)
            let approved = SeerrRequest(id: 2, status: .approved, requestedBy: 7)
            let someoneElse = SeerrRequest(id: 3, status: .pending, requestedBy: 8)

            #expect(SeerrRequest.availability(.unknown, requests: [pending], user: 7) == .pending)
            #expect(SeerrRequest.availability(.unknown, requests: [approved], user: 7) == .processing)
            #expect(SeerrRequest.availability(.unknown, requests: [someoneElse], user: 7) == .unknown)
            #expect(SeerrRequest.availability(.available, requests: [pending], user: 7) == .available)
        }

        @Test func `the Requests page lists each request with its title`() async throws {
            let seerr = try await connection(to: "list.seerr.test") { request in
                switch request.path {
                case "/api/v1/request":
                    .json(#"""
                    {"pageInfo":{"page":1,"pages":1,"results":3},"results":[
                      {"id":2,"status":2,"type":"tv","media":{"tmdbId":1399},"requestedBy":{"id":7}},
                      {"id":1,"status":1,"type":"movie","media":{"tmdbId":550},"requestedBy":{"id":7}},
                      {"id":3,"status":1,"type":"movie","media":{"tmdbId":404}}
                    ]}
                    """#)
                case "/api/v1/tv/1399":
                    .json(Self.series)
                case "/api/v1/movie/550":
                    .json(#"{"id":550,"title":"Fight Club","runtime":139}"#)
                default:
                    .status(404)
                }
            }

            let page = try await seerr.requests()

            #expect(page.items.map(\.item.title) == ["Thrones", "Fight Club"])
            #expect(page.items.map(\.request.status) == [.approved, .pending])
            #expect(page.end == 3)
            #expect(page.hasMore == false)
            let sent = SeerrMockServer.requests(to: "list.seerr.test").first { $0.path == "/api/v1/request" }
            #expect(sent?.query == ["take": "20", "skip": "0"])
        }

        @Test func `without Seerr's count, a full page of requests may have more`() async throws {
            let seerr = try await connection(to: "uncounted.seerr.test") { request in
                switch request.path {
                case "/api/v1/request":
                    .json(#"{"results":[{"id":1,"status":1,"type":"movie","media":{"tmdbId":550}}]}"#)
                case "/api/v1/movie/550":
                    .json(#"{"id":550,"title":"Fight Club"}"#)
                default:
                    .status(404)
                }
            }

            let full = try await seerr.requests(skip: 4, take: 1)
            let short = try await seerr.requests(skip: 4, take: 2)

            #expect(full.end == 5)
            #expect(full.hasMore)
            #expect(short.hasMore == false)
        }
    }

    struct SeerrSeasonTests {
        @Test func `a declined request lets its owner ask again`() {
            let declined = SeerrRequest(id: 1, status: .declined, requestedBy: 7, seasons: [1: .declined])

            let seasons = SeerrSeason.seasons(
                [SeasonFacts(number: 1)],
                known: [],
                requests: [declined],
                user: 7,
                is4K: false,
            )

            #expect(seasons.first?.availability == .unknown)
            #expect(seasons.first?.isRequestable == true)
        }

        @Test func `an approved season is processing and can't be asked for`() {
            let approved = SeerrRequest(id: 1, status: .approved, requestedBy: 8, seasons: [1: .approved])

            let seasons = SeerrSeason.seasons(
                [SeasonFacts(number: 1)],
                known: [],
                requests: [approved],
                user: 7,
                is4K: false,
            )

            #expect(seasons.first?.availability == .processing)
            #expect(seasons.first?.isRequestable == false)
        }

        @Test func `the user's own pending request keeps its seasons whatever is listed after it`() {
            let own = SeerrRequest(id: 1, status: .pending, requestedBy: 7, seasons: [1: .pending, 2: .pending])
            let approved = SeerrRequest(id: 2, status: .approved, requestedBy: 8, seasons: [1: .approved])
            let declined = SeerrRequest(id: 3, status: .declined, requestedBy: 8, seasons: [2: .declined])
            let facts = [SeasonFacts(number: 1), SeasonFacts(number: 2), SeasonFacts(number: 3)]

            for requests in [[own, approved, declined], [approved, declined, own]] {
                let seasons = SeerrSeason.seasons(facts, known: [], requests: requests, user: 7, is4K: false)

                #expect(seasons.map(\.isRequestable) == [true, true, true])
                #expect(seasons.map(\.isInOwnRequest) == [true, true, false])
            }
        }

        @Test func `another user's request holds a season unless the user's own was declined, in any order`() {
            let declined = SeerrRequest(id: 1, status: .declined, requestedBy: 7, seasons: [1: .declined, 2: .declined])
            let others = SeerrRequest(id: 2, status: .pending, requestedBy: 8, seasons: [2: .pending])
            let facts = [SeasonFacts(number: 1), SeasonFacts(number: 2)]

            for requests in [[declined, others], [others, declined]] {
                let seasons = SeerrSeason.seasons(facts, known: [], requests: requests, user: 7, is4K: false)

                #expect(seasons.map(\.isRequestable) == [true, false])
                #expect(seasons.map(\.isInOwnRequest) == [false, false])
            }
        }

        @Test func `4K requests only count for 4K seasons`() {
            let request = SeerrRequest(id: 1, status: .pending, is4K: true, requestedBy: 8, seasons: [1: .pending])
            let facts = [SeasonFacts(number: 1, status: 5, status4K: 1)]

            let standard = SeerrSeason.seasons(facts, known: [], requests: [request], user: 7, is4K: false)
            let fourK = SeerrSeason.seasons(facts, known: [], requests: [request], user: 7, is4K: true)

            #expect(standard.first?.availability == .available)
            #expect(fourK.first?.availability == .pending)
        }
    }
#endif
