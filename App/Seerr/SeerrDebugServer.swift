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
    /// - `many`: as `YES`, with 45 more requests, so the Requests page reads three pages;
    /// - `shared`: as `YES`, with Harbor Town's season 2 in the user's pending request and in
    ///   another user's approved request listed after it.
    ///
    /// It answers Seerr's API for `https://seerr.mock` from a few made-up titles
    /// (`SeerrDebugData.swift`), and keeps the requests made to it until the app quits. It has
    /// no images, so cards show their titles.
    final nonisolated class SeerrDebugServer: URLProtocol {
        static let host = "seerr.mock"

        private static var mode: String? {
            UserDefaults.standard.string(forKey: "seerrMock")?.lowercased()
        }

        /// The plugin settings to use instead of the server's, when mocking.
        static var pluginSettings: SeerrPluginSettings? {
            switch mode {
            case "yes", "plugin", "failing", "many", "shared":
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
