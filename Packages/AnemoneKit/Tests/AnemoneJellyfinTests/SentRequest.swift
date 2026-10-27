import Foundation
import Synchronization

/// The requests a test's fake server saw: the last one, and with `record(_:)` every one.
final class Recorder: Sendable {
    let last = Mutex<SentRequest?>(nil)
    private let all = Mutex<[SentRequest]>([])

    var request: SentRequest? {
        last.withLock(\.self)
    }

    /// Every request recorded with `record(_:)`, in the order the server saw them.
    var requests: [SentRequest] {
        all.withLock(\.self)
    }

    /// Notes a request as the last one and adds it to the rest. Returns what was noted, for a
    /// fake server that answers by the request's path or query.
    @discardableResult
    func record(_ request: URLRequest) -> SentRequest {
        let sent = SentRequest(request)
        last.withLock { $0 = sent }
        all.withLock { $0.append(sent) }
        return sent
    }
}

/// What a test saw of a request.
struct SentRequest: Sendable {
    let method: String?
    let path: String
    let query: [String: String]
    /// Kept as data, since a decoded JSON dictionary isn't `Sendable`.
    let body: Data

    init(_ request: URLRequest) {
        method = request.httpMethod
        path = request.url?.path() ?? ""
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
