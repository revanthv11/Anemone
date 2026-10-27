#if DEBUG && ANEMONE_SEERR
    import AnemoneCore
    import Foundation
    import Synchronization

    /// A made-up Seerr server inside the app, for trying the Seerr pages without one, as
    /// `HomeDebugData` stands in for what the demo server lacks. Launch with `-seerrMock <mode>`:
    ///
    /// - `YES`: the companion plugin seems to set it up with an API key, so the profile signs in
    ///   to it at once ("Managed by server");
    /// - `url`: the plugin gives only its address, which Settings › Seerr › Add offers;
    /// - `failing`: the plugin's sign-in is turned down, so Settings offers Retry;
    /// - `lapsing`: the plugin gives a shared account, whose first session lapses as soon as it's
    ///   used, so the app has to sign in again;
    /// - `many`: as `YES`, with 45 more requests, so the Requests page reads three pages.
    ///
    /// It answers Seerr's API for `https://seerr.mock` from a few made-up titles, and keeps the
    /// requests made to it until the app quits. It has no images, so cards show their titles.
    final nonisolated class SeerrDebugServer: URLProtocol {
        static let host = "seerr.mock"

        private static var mode: String? {
            UserDefaults.standard.string(forKey: "seerrMock")?.lowercased()
        }

        /// The plugin settings to use instead of the server's, when mocking.
        static var pluginSettings: SeerrPluginSettings? {
            switch mode {
            case "yes", "plugin", "failing", "many":
                SeerrPluginSettings(serverURL: "https://\(host)", login: .apiKey("debug"))
            case "lapsing":
                SeerrPluginSettings(serverURL: "https://\(host)", login: .local(username: "debug", password: "debug"))
            case "url":
                SeerrPluginSettings(serverURL: "https://\(host)", login: .none)
            default:
                nil
            }
        }

        /// Sends the Seerr client's requests here when mocking.
        static func install(in configuration: URLSessionConfiguration) {
            guard pluginSettings != nil else { return }
            configuration.protocolClasses = [SeerrDebugServer.self] + (configuration.protocolClasses ?? [])
        }

        override static func canInit(with request: URLRequest) -> Bool {
            request.url?.host() == host
        }

        override static func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            var headers = ["Content-Type": "application/json"]
            let (status, body) = Self.session(request, headers: &headers) ?? Self.answer(request)
            guard let url = request.url,
                  let response = HTTPURLResponse(
                      url: url,
                      statusCode: status,
                      httpVersion: "HTTP/1.1",
                      headerFields: headers,
                  )
            else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}

        /// The `lapsing` mode's sign-ins: how many, and the session cookie of the latest.
        private struct Sessions {
            var count = 0
            var cookie: String?
        }

        private static let sessions = Mutex(Sessions())

        /// In `lapsing` mode, signs in with a password, then lets the first session lapse as soon
        /// as it's used, as when Seerr restarts, so the app has to sign in again. `nil` to answer
        /// as usual.
        private static func session(_ request: URLRequest, headers: inout [String: String]) -> (Int, Data)? {
            let path = request.url?.path() ?? ""
            guard mode == "lapsing", path != "/api/v1/settings/public" else { return nil }
            let forbidden = (403, MockSeerr.json(["message": "Forbidden"]))
            return sessions.withLock { sessions -> (Int, Data)? in
                if request.httpMethod == "POST", path == "/api/v1/auth/local" {
                    sessions.count += 1
                    let cookie = "connect.sid=mock\(sessions.count)"
                    sessions.cookie = cookie
                    headers["Set-Cookie"] = "\(cookie); Path=/; HttpOnly"
                    return (200, MockSeerr.json(["id": 1, "username": "debug", "permissions": 32 | 1024]))
                }
                guard let cookie = sessions.cookie, request.value(forHTTPHeaderField: "Cookie") == cookie else {
                    return forbidden
                }
                if sessions.count == 1, path != "/api/v1/auth/me" {
                    sessions.cookie = nil
                    return forbidden
                }
                return nil
            }
        }

        /// The titles in each of the Discover page's lists.
        private static let lists: [String: [Int]] = [
            "/api/v1/discover/trending": [9101, 9002, 9001, 9102, 9003, 9103, 9004],
            "/api/v1/discover/movies": [9001, 9003, 9004, 9005],
            "/api/v1/discover/movies/upcoming": [9002],
            "/api/v1/discover/tv": [9101, 9103],
            "/api/v1/discover/tv/upcoming": [9102],
        ]

        private static func answer(_ request: URLRequest) -> (Int, Data) {
            let path = request.url?.path() ?? ""
            let method = request.httpMethod ?? "GET"
            if mode == "failing", path.hasSuffix("/auth/me") {
                return (403, MockSeerr.json(["message": "Forbidden"]))
            }
            return MockSeerr.state.withLock { state in
                if method == "GET", let ids = lists[path] {
                    return (200, MockSeerr.page(state, ids: ids))
                }
                switch (method, path) {
                case ("GET", "/api/v1/settings/public"):
                    return (200, MockSeerr.json(["movie4kEnabled": true, "series4kEnabled": false]))
                case ("GET", "/api/v1/auth/me"):
                    // May request, and request in 4K.
                    return (200, MockSeerr.json(["id": 1, "username": "debug", "permissions": 32 | 1024]))
                case ("GET", "/api/v1/search"):
                    let query = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
                        .queryItems?.first { $0.name == "query" }?.value ?? ""
                    return (200, MockSeerr.search(query, state))
                case ("GET", "/api/v1/request"):
                    let query = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
                        .queryItems ?? []
                    return (200, MockSeerr.requests(state, query: query))
                case ("POST", "/api/v1/request"):
                    return MockSeerr.add(request.bodyJSON, to: &state)
                default:
                    let parts = path.split(separator: "/").map(String.init)
                    return MockSeerr.answer(method, parts, body: request.bodyJSON, &state)
                }
            }
        }
    }

    /// The made-up server's titles and requests, and its answers.
    private nonisolated enum MockSeerr {
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
        }

        struct State {
            var titles: [Int: Title]
            var requests: [Request]
            var nextRequestID = 600
        }

        static let state = Mutex(State(
            titles: Dictionary(uniqueKeysWithValues: titles.map { ($0.id, $0) }),
            requests: manyRequests + [Request(id: 501, titleID: 9003, isMovie: true, seasons: [], is4K: false)],
        ))

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
                "status": 1,
                "type": request.isMovie ? "movie" : "tv",
                "is4k": request.is4K,
                "requestedBy": ["id": 1, "username": "debug"],
                "seasons": request.seasons.map { ["seasonNumber": $0, "status": 1] },
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

    private extension URLRequest {
        /// The body as a JSON object. URLProtocol sees a request's body as a stream.
        nonisolated var bodyJSON: [String: Any] {
            var data = httpBody ?? Data()
            if let stream = httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    guard count > 0 else { break }
                    data.append(buffer, count: count)
                }
            }
            return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        }
    }
#endif
