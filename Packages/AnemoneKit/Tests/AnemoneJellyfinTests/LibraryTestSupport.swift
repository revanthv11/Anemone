import AnemoneJellyfin
import Foundation
import Synchronization

/// A session on a fake server for the library tests.
func librarySession(host: String) throws -> JellyfinSession {
    guard let url = URL(string: "https://\(host)") else { throw URLError(.badURL) }
    return JellyfinSession(
        serverURL: url,
        userID: "u1",
        accessToken: "tok",
        identity: ClientIdentity(deviceName: "Test TV", deviceID: "device-1", appVersion: "0.1.0"),
        sessionConfiguration: { MockServer.sessionConfiguration() },
    )
}

/// The requests a fake server saw, in order.
final class RequestLog: Sendable {
    private let requests = Mutex<[SeenRequest]>([])

    func withLock<Result>(_ body: (inout [SeenRequest]) -> Result) -> Result {
        requests.withLock { body(&$0) }
    }
}

/// A request a fake server saw: its path, and every value of each query parameter in order.
struct SeenRequest: Sendable {
    let path: String
    let query: [String: [String]]

    init(_ request: URLRequest) {
        path = request.url?.path() ?? ""
        query = request.queryLists
    }
}

extension URLRequest {
    /// Every value of each query parameter, in order; the SDK repeats a key for each list item.
    var queryLists: [String: [String]] {
        let items = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        return Dictionary(grouping: items, by: \.name).mapValues { $0.map { $0.value ?? "" } }
    }
}
