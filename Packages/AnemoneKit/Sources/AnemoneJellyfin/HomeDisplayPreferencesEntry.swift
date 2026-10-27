import Foundation
import Get
import JellyfinAPI

/// A DisplayPreferences entry, read and written as plain JSON. jellyfin-sdk-swift 3.3.0 types
/// `CustomPrefs` as `[String: String]`, but Jellyfin puts nulls in it (it always adds `tvhome`),
/// which that type can't decode. Fields this app doesn't use go back to the server as they came.
struct DisplayPreferencesEntry: Codable, Sendable {
    private var fields: [String: JSONValue]

    init(from decoder: any Decoder) throws {
        fields = try [String: JSONValue](from: decoder)
    }

    func encode(to encoder: any Encoder) throws {
        try fields.encode(to: encoder)
    }

    /// The custom preferences that have a value.
    var customPrefs: [String: String] {
        get {
            guard case let .object(prefs) = fields["CustomPrefs"] else { return [:] }
            return prefs.compactMapValues { value in
                if case let .string(text) = value {
                    text
                } else {
                    nil
                }
            }
        }
        set {
            fields["CustomPrefs"] = .object(newValue.mapValues(JSONValue.string))
        }
    }
}

extension JellyfinSession {
    func displayPreferences(client: String, id: String) async throws -> DisplayPreferencesEntry {
        let request = Paths.getDisplayPreferences(displayPreferencesID: id, userID: userID, client: client)
        let data: Data
        do {
            data = try await self.client.data(for: request).value
        } catch APIError.unacceptableStatusCode(401) {
            throw SessionError.signedOut
        }
        return try JSONDecoder().decode(DisplayPreferencesEntry.self, from: data)
    }

    func saveDisplayPreferences(_ entry: DisplayPreferencesEntry, client: String, id: String) async throws {
        try await send(Request<Void>(
            path: "/DisplayPreferences/\(id)",
            method: .post,
            query: [("userId", userID), ("client", client)],
            body: entry,
        ))
    }
}

/// Any JSON value, so an entry's fields survive being read and written back.
enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = try .object(container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .int(value): try container.encode(value)
        case let .double(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }
}
