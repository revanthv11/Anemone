import Foundation

/// A fake server that holds back its answer to a request `isPaired` picks until a second such
/// request is out, or 5 s have passed, then answers both: two requests sent together are out at
/// once, while one sent only after the other's answer never is. `MockServer`'s handlers answer
/// at once, on the one thread URL loading gives every fake server, so they can't wait for
/// another request themselves.
final class PairedRequests: URLProtocol {
    typealias Handler = @Sendable (SentRequest) -> MockServer.Reply

    private struct Host {
        let isPaired: @Sendable (SentRequest) -> Bool
        let reply: Handler
        var held: PairedRequests?
        var wereTogether = false
    }

    /// A lock around the hosts with a plain `inout`: `Mutex.withLock`'s `inout sending` makes
    /// Xcode 26.6 reject storing `self` in its state, as in `TopShelfTests`.
    private final class Hosts: @unchecked Sendable {
        private let lock = NSLock()
        private var hosts: [String: Host] = [:]

        func withLock<Result>(_ body: (inout [String: Host]) -> Result) -> Result {
            lock.lock()
            defer { lock.unlock() }
            return body(&hosts)
        }
    }

    private static let hosts = Hosts()

    static func register(
        host: String,
        isPaired: @escaping @Sendable (SentRequest) -> Bool,
        reply: @escaping Handler,
    ) {
        hosts.withLock { $0[host] = Host(isPaired: isPaired, reply: reply) }
    }

    /// Whether two of the requests `isPaired` picks were out at once.
    static func wereTogether(host: String) -> Bool {
        hosts.withLock { $0[host]?.wereTogether ?? false }
    }

    static func sessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PairedRequests.self]
        return configuration
    }

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let host = request.url?.host(),
              let isPaired = Self.hosts.withLock({ $0[host]?.isPaired })
        else { return }
        guard isPaired(SentRequest(request)) else { return answer() }
        let held = Self.hosts.withLock { hosts in
            guard let other = hosts[host]?.held else {
                hosts[host]?.held = self
                return PairedRequests?.none
            }
            hosts[host]?.held = nil
            hosts[host]?.wereTogether = true
            return other
        }
        guard let held else {
            // Only the lock's state and the loading system's client are touched from there.
            nonisolated(unsafe) let waiting = self
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                let isHeld = Self.hosts.withLock { hosts in
                    guard hosts[host]?.held === waiting else { return false }
                    hosts[host]?.held = nil
                    return true
                }
                if isHeld {
                    waiting.answer()
                }
            }
            return
        }
        held.answer()
        answer()
    }

    override func stopLoading() {}

    private func answer() {
        guard let url = request.url,
              let host = url.host(),
              let handler = Self.hosts.withLock({ $0[host]?.reply }),
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: 200,
                  httpVersion: nil,
                  headerFields: ["Content-Type": "application/json"],
              )
        else { return }
        let reply = handler(SentRequest(request))
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
