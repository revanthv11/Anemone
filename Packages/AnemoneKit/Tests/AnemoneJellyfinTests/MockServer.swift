import Foundation
import Synchronization

/// Fakes Jellyfin servers for tests. Each test registers its own host name, so tests running in
/// parallel don't see each other's responses.
final class MockServer: URLProtocol {
    struct Reply {
        let status: Int
        let body: String
    }

    /// Returns `nil` to simulate a connection failure.
    typealias Handler = @Sendable (URLRequest) -> Reply?

    private static let handlers = Mutex<[String: Handler]>([:])

    static func register(host: String, handler: @escaping Handler) {
        handlers.withLock { $0[host] = handler }
    }

    static func sessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockServer.self]
        return configuration
    }

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url, let host = url.host(),
              let handler = Self.handlers.withLock({ $0[host] }),
              let reply = handler(request),
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: reply.status,
                  httpVersion: nil,
                  headerFields: ["Content-Type": "application/json"],
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

extension MockServer.Reply {
    static func json(_ body: String) -> Self {
        Self(status: 200, body: body)
    }

    static func publicInfo(
        name: String = "Living Room",
        version: String = "12.3.0",
        product: String = "Jellyfin Server",
        wizardDone: Bool = true,
    ) -> Self {
        .json("""
        {"Id":"srv1","ServerName":"\(name)","Version":"\(version)",
         "ProductName":"\(product)","StartupWizardCompleted":\(wizardDone)}
        """)
    }

    static func authentication(token: String = "tok", userID: String = "u1", name: String = "Alice") -> Self {
        .json(#"{"AccessToken":"\#(token)","ServerId":"srv1","User":{"Id":"\#(userID)","Name":"\#(name)"}}"#)
    }

    static let unauthorized = Self(status: 401, body: "")
}
