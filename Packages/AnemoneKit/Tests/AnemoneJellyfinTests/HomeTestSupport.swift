@testable import AnemoneJellyfin
import Foundation
import Synchronization
import Testing

/// A fake server for home page tests: answers by path and keeps every request it saw.
final class HomeServer: Sendable {
    struct Seen: Sendable {
        let path: String
        let request: SentRequest
    }

    /// A reference, so the server's handler can share it.
    private final class Log: Sendable {
        let seen = Mutex<[Seen]>([])
    }

    let host: String
    private let log = Log()

    init(_ host: String, routes: @escaping @Sendable (_ path: String, _ request: SentRequest) -> MockServer.Reply?) {
        self.host = host
        MockServer.register(host: host) { [log] request in
            let path = request.url?.path() ?? ""
            let sent = SentRequest(request)
            log.seen.withLock { $0.append(Seen(path: path, request: sent)) }
            return routes(path, sent)
        }
    }

    func session() throws -> JellyfinSession {
        try JellyfinSession(
            serverURL: #require(URL(string: "https://\(host)")),
            userID: "u1",
            accessToken: "tok",
            identity: ClientIdentity(deviceName: "Test TV", deviceID: "device-1", appVersion: "0.1.0"),
            sessionConfiguration: { MockServer.sessionConfiguration() },
        )
    }

    /// The requests made to `path`, in order.
    func requests(to path: String) -> [SentRequest] {
        log.seen.withLock { $0.filter { $0.path == path }.map(\.request) }
    }

    var paths: [String] {
        log.seen.withLock { $0.map(\.path) }
    }
}

extension MockServer.Reply {
    static func homeItems(_ items: String...) -> Self {
        .json(#"{"Items":[\#(items.joined(separator: ","))]}"#)
    }

    static let notFound = Self(status: 404, body: "")

    /// A DisplayPreferences entry with these custom prefs.
    static func displayPreferences(_ prefs: [String: String] = [:]) -> Self {
        let data = (try? JSONSerialization.data(withJSONObject: ["Id": "default", "CustomPrefs": prefs])) ?? Data()
        return .json(String(bytes: data, encoding: .utf8) ?? "")
    }
}

enum HomeFixtures {
    static let views = #"""
    {"Items":[
      {"Id":"movies","Name":"Movies","CollectionType":"movies"},
      {"Id":"shows","Name":"Shows","CollectionType":"tvshows"},
      {"Id":"live","Name":"Live TV","CollectionType":"livetv"}
    ]}
    """#

    static func movie(_ id: String = "m1", lastPlayed: String? = nil) -> String {
        let played = lastPlayed.map { #","LastPlayedDate":"\#($0)""# } ?? ""
        return #"""
        {"Id":"\#(id)","Name":"Film \#(id)","Type":"Movie","ProductionYear":2024,
         "ImageTags":{"Primary":"p"},"UserData":{"Key":"\#(id)","PlayedPercentage":42.5\#(played)}}
        """#
    }

    static func episode(
        _ id: String = "e1",
        series: String = "series",
        lastPlayed: String? = nil,
        premiere: String? = nil,
    ) -> String {
        let played = lastPlayed.map { #","LastPlayedDate":"\#($0)""# } ?? ""
        let premiereDate = premiere.map { #","PremiereDate":"\#($0)""# } ?? ""
        return #"""
        {"Id":"\#(id)","Name":"Episode \#(id)","Type":"Episode","SeriesId":"\#(series)","SeriesName":"Show",
         "ParentIndexNumber":1,"IndexNumber":3,"ImageTags":{"Primary":"still"}\#(premiereDate),
         "UserData":{"Key":"\#(id)"\#(played)}}
        """#
    }
}

/// Dates as the server writes them.
func serverDate(daysAgo days: Double, from now: Date = .now) -> String {
    now.addingTimeInterval(-days * 86400).formatted(.iso8601)
}
