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
    /// Something answered, but it's another product (such as Emby), not Jellyfin.
    case notJellyfin(String)
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

    /// Probes every candidate from `ServerAddress.candidates(for:)` at once and uses the
    /// highest-priority one that answers, so a blocked HTTPS port doesn't delay the HTTP fallback.
    public func connect(to address: String) async throws(ServerConnectionError) -> ConnectedServer {
        let candidates = ServerAddress.candidates(for: address)
        guard !candidates.isEmpty else { throw .invalidAddress }
        guard let (url, info) = await firstAnswer(from: candidates) else { throw .unreachable }

        // From here on this is the server that was meant, so problems are reported, not skipped.
        if let product = info.productName, product != Self.jellyfinProductName {
            throw .notJellyfin(product)
        }
        guard let id = info.id, let versionString = info.version else { throw .unreachable }
        guard let version = ServerVersion(versionString), version.isSupported else {
            throw .unsupportedVersion(versionString)
        }
        guard info.isStartupWizardCompleted != false else { throw .setupIncomplete }
        return ConnectedServer(id: id, name: info.serverName ?? url.host() ?? id, version: versionString, url: url)
    }

    private static let jellyfinProductName = "Jellyfin Server"

    /// The first candidate, in priority order, that answers. Returns as soon as every
    /// higher-priority candidate has failed, and cancels the probes still running.
    private func firstAnswer(from candidates: [URL]) async -> (URL, PublicSystemInfo)? {
        await withTaskGroup(of: (Int, PublicSystemInfo?).self) { group in
            for (index, url) in candidates.enumerated() {
                group.addTask { await (index, publicInfo(at: url)) }
            }
            // nil: still waiting; .some(nil): failed; .some(info): answered.
            var results = [PublicSystemInfo??](repeating: nil, count: candidates.count)
            for await (index, info) in group {
                results[index] = .some(info)
                for (position, result) in results.enumerated() {
                    guard let result else { break }
                    if let info = result {
                        group.cancelAll()
                        return (candidates[position], info)
                    }
                }
            }
            return nil
        }
    }

    private func publicInfo(at url: URL) async -> PublicSystemInfo? {
        let configuration = makeSessionConfiguration()
        configuration.timeoutIntervalForRequest = Self.timeout
        let client = identity.makeClient(serverURL: url, sessionConfiguration: configuration)
        return try? await client.send(Paths.getPublicSystemInfo).value
    }
}
