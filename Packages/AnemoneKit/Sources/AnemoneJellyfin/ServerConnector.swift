import AnemoneCore
import Foundation
import JellyfinAPI

/// A server that answered and passed Anemone's checks.
public struct ConnectedServer: Equatable, Sendable {
    public let id: String
    public let name: String
    public let version: String
    public let url: URL

    public init(id: String, name: String, version: String, url: URL) {
        self.id = id
        self.name = name
        self.version = version
        self.url = url
    }
}

public enum ServerConnectionError: Error, Equatable {
    /// The text isn't a URL or host name.
    case invalidAddress
    /// Nothing answered as a Jellyfin server at any candidate URL.
    case unreachable
    /// The server runs a release older than `ServerVersion.minimumSupported`.
    case unsupportedVersion(String)
    /// The server's startup wizard hasn't been finished, so it can't sign anyone in yet.
    case setupIncomplete
}

/// Finds the Jellyfin server behind an address someone typed, like Wholphin's "add server" step.
public struct ServerConnector: Sendable {
    /// How long to wait on each candidate URL, matching Wholphin.
    public static let timeout: TimeInterval = 6

    private let identity: ClientIdentity
    private let makeSessionConfiguration: @Sendable () -> URLSessionConfiguration

    public init(
        identity: ClientIdentity,
        sessionConfiguration: @escaping @Sendable () -> URLSessionConfiguration = { .default },
    ) {
        self.identity = identity
        makeSessionConfiguration = sessionConfiguration
    }

    /// Tries each of `ServerAddress.candidates(for:)` in turn and returns the first Jellyfin server found.
    public func connect(to address: String) async throws(ServerConnectionError) -> ConnectedServer {
        let candidates = ServerAddress.candidates(for: address)
        guard !candidates.isEmpty else { throw .invalidAddress }

        for url in candidates {
            guard let info = await publicInfo(at: url), let id = info.id, let versionString = info.version else {
                continue
            }
            // From here on this is the right server, so problems are reported rather than skipped.
            guard let version = ServerVersion(versionString), version.isSupported else {
                throw .unsupportedVersion(versionString)
            }
            guard info.isStartupWizardCompleted != false else { throw .setupIncomplete }
            return ConnectedServer(id: id, name: info.serverName ?? url.host() ?? id, version: versionString, url: url)
        }
        throw .unreachable
    }

    private func publicInfo(at url: URL) async -> PublicSystemInfo? {
        let configuration = makeSessionConfiguration()
        configuration.timeoutIntervalForRequest = Self.timeout
        let client = identity.makeClient(serverURL: url, sessionConfiguration: configuration)
        return try? await client.send(Paths.getPublicSystemInfo).value
    }
}
