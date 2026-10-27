#if ANEMONE_SEERR
    @testable import AnemoneSeerr
    import Foundation
    import Testing

    /// A connection to a fake Seerr at `host`, signed in with an API key.
    func connection(
        to host: String,
        permissions: Int = 32,
        settings: String = SeerrJSON.publicSettings,
        other: @escaping @Sendable (Sent) -> SeerrMockServer.Reply?,
    ) async throws -> SeerrConnection {
        SeerrMockServer.register(host: host, handler: SeerrJSON.server(
            permissions: permissions,
            settings: settings,
            other: other,
        ))
        return try await SeerrConnection.signIn(
            to: #require(URL(string: "https://\(host)/")),
            with: .apiKey("key"),
            configuration: SeerrMockServer.configuration(),
        )
    }

    struct SeerrDiscoverTests {
        private static let mixedResults = #"""
        {"page":1,"totalPages":1,"totalResults":3,"results":[
          {"id":603,"mediaType":"movie","title":"The Matrix","releaseDate":"1999-03-30",
           "posterPath":"/matrix.jpg","backdropPath":"/matrix-back.jpg",
           "mediaInfo":{"status":5,"jellyfinMediaId":"C002F0F8-8EE9-70CC-E7F1-38BBC925DE64"}},
          {"id":603,"mediaType":"tv","name":"Matrix","firstAirDate":"1993-03-01","posterPath":"/tv.jpg"},
          {"id":6384,"mediaType":"person","name":"Keanu Reeves","profilePath":"/keanu.jpg"}
        ]}
        """#

        @Test func `trending mixes movies and series and leaves people out`() async throws {
            let seerr = try await connection(to: "trending.seerr.test") { request in
                request.path == "/api/v1/discover/trending" ? .json(Self.mixedResults) : nil
            }

            let items = try await seerr.discover(.trending)

            #expect(items.map(\.id) == ["movie-603", "tv-603"])
            let movie = try #require(items.first)
            #expect(movie.title == "The Matrix")
            #expect(movie.year == 1999)
            #expect(movie.availability == .available)
            #expect(movie.jellyfinItemID == "c002f0f88ee970cce7f138bbc925de64")
            #expect(movie.posterURL?.absoluteString == "https://image.tmdb.org/t/p/w500/matrix.jpg")
            #expect(
                movie.backdropURL?.absoluteString
                    == "https://image.tmdb.org/t/p/w1920_and_h1080_multi_faces/matrix-back.jpg",
            )
            #expect(items[1].title == "Matrix")
            #expect(items[1].availability == .unknown)
            let sent = SeerrMockServer.requests(to: "trending.seerr.test").last
            #expect(sent?.query["page"] == "1")
        }

        @Test func `each row reads its own list`() async throws {
            let seerr = try await connection(to: "rows.seerr.test") { request in
                switch request.path {
                case "/api/v1/discover/movies", "/api/v1/discover/movies/upcoming":
                    .json(#"{"results":[{"id":1,"mediaType":"movie","title":"A"}]}"#)
                case "/api/v1/discover/tv", "/api/v1/discover/tv/upcoming":
                    .json(#"{"results":[{"id":2,"mediaType":"tv","name":"B"}]}"#)
                default:
                    nil
                }
            }

            #expect(try await seerr.discover(.popularMovies).map(\.id) == ["movie-1"])
            #expect(try await seerr.discover(.upcomingMovies, page: 2).map(\.id) == ["movie-1"])
            #expect(try await seerr.discover(.popularSeries).map(\.id) == ["tv-2"])
            #expect(try await seerr.discover(.upcomingSeries).map(\.id) == ["tv-2"])
            let paths = SeerrMockServer.requests(to: "rows.seerr.test").suffix(4).map(\.path)
            #expect(paths == [
                "/api/v1/discover/movies",
                "/api/v1/discover/movies/upcoming",
                "/api/v1/discover/tv",
                "/api/v1/discover/tv/upcoming",
            ])
            #expect(SeerrMockServer.requests(to: "rows.seerr.test").suffix(3).first?.query["page"] == "2")
        }

        @Test func `search sends the query and keeps movies and series`() async throws {
            let seerr = try await connection(to: "search.seerr.test") { request in
                request.path == "/api/v1/search" ? .json(Self.mixedResults) : nil
            }

            let items = try await seerr.search("matrix")

            #expect(items.map(\.kind) == [.movie, .series])
            #expect(SeerrMockServer.requests(to: "search.seerr.test").last?.query["query"] == "matrix")
        }

        @Test func `images come through Seerr when it caches them`() async throws {
            let seerr = try await connection(
                to: "cache.seerr.test",
                settings: #"{"cacheImages":true}"#,
            ) { request in
                request.path == "/api/v1/discover/movies" ? .json(Self.mixedResults) : nil
            }

            let movie = try #require(try await seerr.discover(.popularMovies).first)

            #expect(movie.posterURL?.absoluteString == "https://cache.seerr.test/imageproxy/tmdb/t/p/w500/matrix.jpg")
        }

        @Test func `similar titles are looked up by kind`() async throws {
            let seerr = try await connection(to: "similar.seerr.test") { request in
                switch request.path {
                case "/api/v1/movie/550/similar":
                    .json(#"{"results":[{"id":1,"mediaType":"movie","title":"A"}]}"#)
                case "/api/v1/tv/1399/similar":
                    .json(#"{"results":[{"id":2,"name":"B"}]}"#)
                default:
                    nil
                }
            }

            #expect(try await seerr.similar(to: 550, kind: .movie).map(\.id) == ["movie-1"])
            #expect(try await seerr.similar(to: 1399, kind: .series).map(\.id) == ["tv-2"])
        }

        @Test func `a person's credits are merged, deduplicated and newest first`() async throws {
            let seerr = try await connection(to: "credits.seerr.test") { request in
                guard request.path == "/api/v1/person/6384/combined_credits" else { return nil }
                return .json(#"""
                {"id":6384,
                 "cast":[
                   {"id":603,"mediaType":"movie","title":"The Matrix","releaseDate":"1999-03-30","character":"Neo"},
                   {"id":10,"mediaType":"tv","name":"Undated"},
                   {"id":245891,"mediaType":"movie","title":"John Wick","releaseDate":"2014-10-22","character":"John"}
                 ],
                 "crew":[
                   {"id":603,"mediaType":"movie","title":"The Matrix","releaseDate":"1999-03-30","job":"Stunts"},
                   {"id":99,"mediaType":"movie","title":"Directed","releaseDate":"2021-01-01","job":"Director"}
                 ]}
                """#)
            }

            let items = try await seerr.similar(to: 6384, kind: .person)

            #expect(items.map(\.title) == ["Directed", "John Wick", "The Matrix", "Undated"])
            #expect(items.first { $0.tmdbID == 603 }?.subtitle == "Neo")
        }

        @Test func `newest first keeps undated titles last in their order`() {
            let items = [
                DiscoverItem(tmdbID: 1, kind: .movie, title: "None A"),
                DiscoverItem(tmdbID: 2, kind: .movie, title: "Old", releaseDate: "1990-01-01"),
                DiscoverItem(tmdbID: 3, kind: .movie, title: "None B"),
                DiscoverItem(tmdbID: 4, kind: .series, title: "New", releaseDate: "2020-01-01"),
            ]

            #expect(SeerrConnection.newestFirst(items).map(\.title) == ["New", "Old", "None A", "None B"])
        }
    }
#endif
