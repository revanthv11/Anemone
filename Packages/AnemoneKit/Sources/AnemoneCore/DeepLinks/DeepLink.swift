import Foundation

/// An `anemone://` link, which the Top Shelf (and anything else) opens Anemone with. Ported
/// from Wholphin's `IntentService`, whose `wholphin://` links have the same three actions:
///
/// - `anemone://item/<id>` opens the item's page;
/// - `anemone://play/<id>` opens it and plays it: from `position` (milliseconds, as in Wholphin)
///   when given, otherwise from where it was left off, which is what Play on a Top Shelf item
///   means (Wholphin starts from the beginning);
/// - `anemone://search?query=<term>` searches for the term.
///
/// Any of them may name the profile it's for with `server=<id>&user=<id>` (Wholphin's
/// `serverId` and `userId`, which are read too), so a link from the Top Shelf opens on the
/// profile whose rows it came from.
public struct DeepLink: Hashable, Sendable {
    public enum Action: Hashable, Sendable {
        case item(id: String)
        case play(id: String, position: Duration?)
        case search(String)
    }

    public static let scheme = "anemone"

    public var action: Action
    public var serverID: String?
    public var userID: String?

    public init(_ action: Action, serverID: String? = nil, userID: String? = nil) {
        self.action = action
        self.serverID = serverID
        self.userID = userID
    }

    /// `nil` unless it's an `anemone://` link with a known action and, for items, a valid ID.
    public init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == Self.scheme,
              let host = components.host?.lowercased()
        else { return nil }
        let query = Query(components.queryItems ?? [])
        // The ID is the path (`item/<id>`), or Wholphin's `itemId` parameter.
        let pathID = components.path.split(separator: "/").first.map(String.init)
        let id = (pathID ?? query["itemId"]).flatMap(Self.validID)

        switch host {
        case "item", "view":
            guard let id else { return nil }
            action = .item(id: id)
        case "play":
            guard let id else { return nil }
            let position = query["position"].flatMap(Int.init).map { Duration.milliseconds(max($0, 0)) }
            action = .play(id: id, position: position)
        case "search":
            action = .search(query["query"] ?? query["q"] ?? "")
        default:
            return nil
        }
        serverID = (query["server"] ?? query["serverId"]).flatMap(Self.validID)
        userID = (query["user"] ?? query["userId"]).flatMap(Self.validID)
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        var items: [URLQueryItem] = []
        switch action {
        case let .item(id):
            components.host = "item"
            components.path = "/\(id)"
        case let .play(id, position):
            components.host = "play"
            components.path = "/\(id)"
            if let position {
                let milliseconds = Int((position / .milliseconds(1)).rounded())
                items.append(URLQueryItem(name: "position", value: String(milliseconds)))
            }
        case let .search(term):
            components.host = "search"
            items.append(URLQueryItem(name: "query", value: term))
        }
        if let serverID {
            items.append(URLQueryItem(name: "server", value: serverID))
        }
        if let userID {
            items.append(URLQueryItem(name: "user", value: userID))
        }
        components.queryItems = items.isEmpty ? nil : items
        // Every part is either fixed or checked, so the URL always forms.
        return components.url ?? URL(fileURLWithPath: "/")
    }

    /// Jellyfin IDs are hex, with or without dashes. Anything else is refused, since IDs end up
    /// in request paths.
    private static func validID(_ text: String) -> String? {
        let isValid = (1 ... 64).contains(text.count)
            && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        return isValid ? text : nil
    }

    private struct Query {
        let items: [URLQueryItem]

        init(_ items: [URLQueryItem]) {
            self.items = items
        }

        /// The first value for the name, ignoring case.
        subscript(name: String) -> String? {
            items.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
    }
}
