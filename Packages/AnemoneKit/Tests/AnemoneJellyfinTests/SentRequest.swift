import Foundation
import Synchronization

/// The last request a test's fake server saw.
final class Recorder: Sendable {
    let last = Mutex<SentRequest?>(nil)

    var request: SentRequest? {
        last.withLock(\.self)
    }
}

/// What a test saw of a request.
struct SentRequest: Sendable {
    let method: String?
    let query: [String: String]
    /// Kept as data, since a decoded JSON dictionary isn't `Sendable`.
    let body: Data

    init(_ request: URLRequest) {
        method = request.httpMethod
        query = request.url?.queryValues ?? [:]
        body = request.bodyData
    }

    /// The body as a JSON object.
    var json: [String: Any] {
        (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
    }
}

extension URL {
    /// The query's values by name. The SDK repeats a key for each value of a list; they're joined
    /// with commas here.
    var queryValues: [String: String] {
        let items = URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }) { "\($0),\($1)" }
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
