import Foundation
import JellyfinAPI

/// A Jellyfin server on the local network that answered discovery. Adding it still goes through
/// `ServerConnector.connect(to:)` with its URL, which checks the version and setup as for a typed address.
public struct DiscoveredServer: Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    /// The address the server gave for itself, such as `http://192.168.1.20:8096`.
    public let url: URL

    public init(id: String, name: String, url: URL) {
        self.id = id
        self.name = name
        self.url = url
    }

    /// Reads a server's reply, such as `{"Address":"http://192.168.1.20:8096","Id":"…","Name":"Den"}`.
    /// Returns nil for anything without an id and an HTTP or HTTPS address, so stray datagrams are ignored.
    init?(reply: Data) {
        guard let info = try? JSONDecoder().decode(ServerDiscoveryInfo.self, from: reply),
              let id = info.id, !id.isEmpty,
              let address = info.address?.trimmingCharacters(in: .whitespacesAndNewlines),
              let components = URLComponents(string: address),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty,
              let url = components.url
        else { return nil }
        let name = info.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.init(id: id, name: name.isEmpty ? host : name, url: url)
    }
}
