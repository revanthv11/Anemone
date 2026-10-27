#if DEBUG && ANEMONE_SEERR
    import Foundation
    import Synchronization

    /// The made-up server's titles and requests, and its answers.
    nonisolated enum MockSeerr {
        struct Title {
            let id: Int
            let isMovie: Bool
            let name: String
            let date: String
            let overview: String
            var status: Int
            var jellyfinID: String?
            /// For series: season number to what the server has of it.
            var seasons: [Int: Int] = [:]
        }

        struct Request {
            let id: Int
            let titleID: Int
            let isMovie: Bool
            var seasons: [Int]
            let is4K: Bool
            var status = 1
            /// The Seerr user who asked: 1 is the signed-in user.
            var requestedBy = 1
        }

        struct State {
            var titles: [Int: Title]
            var requests: [Request]
            var nextRequestID = 600
        }

        static let state = Mutex(State(
            titles: Dictionary(uniqueKeysWithValues: titles.map { ($0.id, $0) }),
            requests: manyRequests + [Request(id: 501, titleID: 9003, isMovie: true, seasons: [], is4K: false)]
                + sharedRequests,
        ))

        /// In `shared` mode, Harbor Town's season 2 in the user's pending request, and in another
        /// user's approved request listed after it.
        private static var sharedRequests: [Request] {
            guard UserDefaults.standard.string(forKey: "seerrMock")?.lowercased() == "shared" else { return [] }
            return [
                Request(id: 502, titleID: 9101, isMovie: false, seasons: [2], is4K: false),
                Request(id: 503, titleID: 9101, isMovie: false, seasons: [2], is4K: false, status: 2, requestedBy: 2),
            ]
        }

        /// In `many` mode, 45 more requests, for each title in turn.
        private static var manyRequests: [Request] {
            guard UserDefaults.standard.string(forKey: "seerrMock")?.lowercased() == "many" else { return [] }
            return (0 ..< 45).map { index in
                let title = titles[index % titles.count]
                return Request(
                    id: 100 + index,
                    titleID: title.id,
                    isMovie: title.isMovie,
                    seasons: title.isMovie ? [] : [1],
                    is4K: false,
                )
            }
        }

        private static let titles = [
            // King Lear is on the demo server, so its card opens its page there.
            Title(
                id: 9001, isMovie: true, name: "King Lear", date: "1953-10-18",
                overview: "Made-up Seerr data: a title already on the Jellyfin server.",
                status: 5, jellyfinID: "b07f6514a3e3aa7d8c273458c9cd4c82",
            ),
            Title(
                id: 9002, isMovie: true, name: "Northern Lights", date: "2027-02-12",
                overview: "Made-up Seerr data: an upcoming movie nobody has asked for.", status: 1,
            ),
            Title(
                id: 9003, isMovie: true, name: "Paper Boats", date: "2023-06-02",
                overview: "Made-up Seerr data: a movie the user asked for, waiting for approval.", status: 2,
            ),
            Title(
                id: 9004, isMovie: true, name: "Night Market", date: "2022-09-30",
                overview: "Made-up Seerr data: a movie nobody has asked for.", status: 1,
            ),
            Title(
                id: 9005, isMovie: true, name: "The Long Field", date: "2021-04-16",
                overview: "Made-up Seerr data: an approved movie on its way.", status: 3,
            ),
            Title(
                id: 9101, isMovie: false, name: "Harbor Town", date: "2019-01-08",
                overview: "Made-up Seerr data: a series with its first season on the server.",
                status: 4, seasons: [1: 5, 2: 1, 3: 1],
            ),
            Title(
                id: 9102, isMovie: false, name: "Signal Lost", date: "2027-05-01",
                overview: "Made-up Seerr data: an upcoming series.", status: 1, seasons: [1: 1],
            ),
            Title(
                id: 9103, isMovie: false, name: "Quiet Hours", date: "2020-11-20",
                overview: "Made-up Seerr data: a series nobody has asked for.", status: 1,
                seasons: [1: 1, 2: 1],
            ),
        ]

        /// A title's page and lists, credits, and changing a request.
        static func answer(
            _ method: String,
            _ path: [String],
            body: [String: Any],
            _ state: inout State,
        ) -> (Int, Data) {
            // The path is ["api", "v1", kind, id, ...].
            guard path.count >= 4, let id = Int(path[3]) else { return (404, json([:])) }
            switch (method, path[2], path.dropFirst(4).first) {
            case ("GET", "movie", nil), ("GET", "tv", nil):
                guard let title = state.titles[id] else { return (404, json([:])) }
                return (200, json(details(title, state)))
            case ("GET", "movie", _?):
                return (200, page(state, ids: [9004, 9005, 9002].filter { $0 != id }))
            case ("GET", "tv", _?):
                return (200, page(state, ids: [9101, 9103, 9102].filter { $0 != id }))
            case ("GET", "person", "combined_credits"?):
                let cast = [9001, 9101, 9004].compactMap { state.titles[$0] }.map { summary($0, state) }
                return (200, json(["id": id, "cast": cast, "crew": []]))
            case ("DELETE", "request", nil):
                state.requests.removeAll { $0.id == id }
                refresh(&state)
                return (204, Data())
            case ("PUT", "request", nil):
                if let index = state.requests.firstIndex(where: { $0.id == id }) {
                    state.requests[index].seasons = body["seasons"] as? [Int] ?? []
                }
                refresh(&state)
                return (200, json(["id": id, "status": 1]))
            default:
                return (404, json([:]))
            }
        }

        static func add(_ body: [String: Any], to state: inout State) -> (Int, Data) {
            guard let id = body["mediaId"] as? Int, let title = state.titles[id] else { return (404, json([:])) }
            let added = Request(
                id: state.nextRequestID,
                titleID: id,
                isMovie: title.isMovie,
                seasons: body["seasons"] as? [Int] ?? [],
                is4K: body["is4k"] as? Bool ?? false,
            )
            state.nextRequestID += 1
            state.requests.append(added)
            refresh(&state)
            return (201, json(requestJSON(added, state)))
        }

        static func search(_ query: String, _ state: State) -> Data {
            let ids = state.titles.values.filter { $0.name.localizedCaseInsensitiveContains(query) }.map(\.id)
            return page(state, ids: ids.sorted())
        }

        /// The requests, newest first, paged by `take` and `skip` as Seerr pages them: 10 at a
        /// time unless asked.
        static func requests(_ state: State, query: [URLQueryItem]) -> Data {
            func number(_ name: String) -> Int? {
                query.first { $0.name == name }?.value.flatMap { Int($0) }
            }
            let take = max(number("take") ?? 10, 1)
            let skip = max(number("skip") ?? 0, 0)
            let all = Array(state.requests.reversed())
            let results = all.dropFirst(skip).prefix(take).map { requestJSON($0, state) }
            return json([
                "pageInfo": ["page": skip / take + 1, "pages": (all.count + take - 1) / take, "results": all.count],
                "results": Array(results),
            ])
        }

        /// A requested movie is pending until approved; a cancelled one is unknown again.
        private static func refresh(_ state: inout State) {
            for (id, title) in state.titles where title.isMovie && title.status <= 2 {
                state.titles[id]?.status = state.requests.contains { $0.titleID == id && !$0.is4K } ? 2 : 1
            }
        }

        static func page(_ state: State, ids: [Int]) -> Data {
            let results = ids.compactMap { state.titles[$0] }.map { summary($0, state) }
            return json(["page": 1, "totalPages": 1, "totalResults": results.count, "results": results])
        }

        private static func summary(_ title: Title, _ state: State) -> [String: Any] {
            var result: [String: Any] = [
                "id": title.id,
                "mediaType": title.isMovie ? "movie" : "tv",
                "overview": title.overview,
                "mediaInfo": mediaInfo(title, state),
            ]
            result[title.isMovie ? "title" : "name"] = title.name
            result[title.isMovie ? "releaseDate" : "firstAirDate"] = title.date
            return result
        }

        private static func details(_ title: Title, _ state: State) -> [String: Any] {
            var result = summary(title, state)
            result["genres"] = [["id": 18, "name": "Drama"]]
            result["voteAverage"] = 7.4
            if title.isMovie {
                result["runtime"] = 104
                result["tagline"] = "Made-up data for trying Anemone's Seerr pages."
            } else {
                result["episodeRunTime"] = [45]
                result["seasons"] = title.seasons.keys.sorted().map { number in
                    ["seasonNumber": number, "name": "Season \(number)", "episodeCount": 8]
                }
            }
            return result
        }

        private static func mediaInfo(_ title: Title, _ state: State) -> [String: Any] {
            let requests = state.requests.filter { $0.titleID == title.id }
            var info: [String: Any] = [
                "tmdbId": title.id,
                "status": title.status,
                "requests": requests.map { requestJSON($0, state, nested: true) },
                "seasons": title.seasons.map { ["seasonNumber": $0.key, "status": $0.value] },
            ]
            info["jellyfinMediaId"] = title.jellyfinID
            return info
        }

        private static func requestJSON(_ request: Request, _ state: State, nested: Bool = false) -> [String: Any] {
            var result: [String: Any] = [
                "id": request.id,
                "status": request.status,
                "type": request.isMovie ? "movie" : "tv",
                "is4k": request.is4K,
                "requestedBy": ["id": request.requestedBy],
                "seasons": request.seasons.map { ["seasonNumber": $0, "status": request.status] },
                "createdAt": "2026-10-20T10:00:00.000Z",
            ]
            if !nested, let title = state.titles[request.titleID] {
                result["media"] = ["tmdbId": title.id, "status": title.status]
            }
            return result
        }

        static func json(_ object: Any) -> Data {
            (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        }
    }
#endif
