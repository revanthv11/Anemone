#if ANEMONE_SEERR
    import Foundation
    import Synchronization

    /// Fakes Seerr servers for tests, as AnemoneJellyfinTests' `MockServer` fakes Jellyfin. Each
    /// test registers its own host name, so tests running in parallel don't see each other's
    /// responses, and every request is recorded.
    final class SeerrMockServer: URLProtocol {
        struct Reply {
            var status: Int
            var body: String
            var headers: [String: String] = [:]

            static func json(_ body: String, headers: [String: String] = [:]) -> Reply {
                Reply(status: 200, body: body, headers: headers)
            }

            static func status(_ status: Int) -> Reply {
                Reply(status: status, body: "{}")
            }
        }

        /// Returns `nil` to simulate a connection failure.
        typealias Handler = @Sendable (Sent) -> Reply?

        private static let handlers = Mutex<[String: Handler]>([:])
        private static let sent = Mutex<[String: [Sent]]>([:])

        static func register(host: String, handler: @escaping Handler) {
            handlers.withLock { $0[host] = handler }
            sent.withLock { $0[host] = [] }
        }

        /// What the server at `host` was sent, in order.
        static func requests(to host: String) -> [Sent] {
            sent.withLock { $0[host] ?? [] }
        }

        static func configuration() -> URLSessionConfiguration {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [SeerrMockServer.self]
            return configuration
        }

        override static func canInit(with _: URLRequest) -> Bool {
            true
        }

        override static func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            let request = Sent(request)
            guard let url = self.request.url, let host = url.host() else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            Self.sent.withLock { $0[host, default: []].append(request) }
            guard let handler = Self.handlers.withLock({ $0[host] }),
                  let reply = handler(request),
                  let response = HTTPURLResponse(
                      url: url,
                      statusCode: reply.status,
                      httpVersion: "HTTP/1.1",
                      headerFields: ["Content-Type": "application/json"].merging(reply.headers) { $1 },
                  )
            else {
                client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    /// What a test saw of a request.
    struct Sent: Sendable {
        let method: String
        let url: URL?
        let path: String
        let query: [String: String]
        let headers: [String: String]
        let body: Data

        init(_ request: URLRequest) {
            method = request.httpMethod ?? "GET"
            url = request.url
            path = request.url?.path() ?? ""
            let items = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
            query = Dictionary(items.map { ($0.name, $0.value ?? "") }) { $1 }
            headers = request.allHTTPHeaderFields ?? [:]
            body = request.bodyData
        }

        /// The body as a JSON object.
        var json: [String: Any] {
            (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
        }

        func header(_ name: String) -> String? {
            headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
    }

    private extension URLRequest {
        /// URLProtocol sees a request's body as a stream.
        var bodyData: Data {
            guard let stream = httpBodyStream else { return httpBody ?? Data() }
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(buffer, count: count)
            }
            return data
        }
    }

    /// Canned Seerr answers.
    enum SeerrJSON {
        static let publicSettings = #"{"initialized":true,"movie4kEnabled":false,"series4kEnabled":false}"#

        static func user(id: Int = 7, name: String = "alice", permissions: Int = 32) -> String {
            #"{"id":\#(id),"username":"\#(name)","email":"alice@example.com","permissions":\#(permissions)}"#
        }

        /// A server that signs in with a password and answers the usual questions, then hands
        /// anything else to `other`.
        static func server(
            permissions: Int = 32,
            settings: String = publicSettings,
            other: @escaping @Sendable (Sent) -> SeerrMockServer.Reply? = { _ in nil },
        ) -> SeerrMockServer.Handler {
            { request in
                switch (request.method, request.path) {
                case ("GET", "/api/v1/settings/public"):
                    .json(settings)
                case ("POST", "/api/v1/auth/local"), ("POST", "/api/v1/auth/jellyfin"):
                    .json(user(permissions: permissions), headers: [
                        "Set-Cookie": "connect.sid=s%3Asecret; Path=/; Expires=Wed, 25 Nov 2026 10:00:00 GMT; HttpOnly",
                    ])
                case ("GET", "/api/v1/auth/me"):
                    .json(user(permissions: permissions))
                default:
                    other(request)
                }
            }
        }
    }
#endif
