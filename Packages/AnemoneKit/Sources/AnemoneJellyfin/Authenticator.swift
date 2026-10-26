import Foundation
import Get
import JellyfinAPI

/// A signed-in Jellyfin user and their access token.
public struct SignedInUser: Equatable, Sendable {
    public let id: String
    public let name: String
    public let primaryImageTag: String?
    public let accessToken: String

    public init(id: String, name: String, primaryImageTag: String?, accessToken: String) {
        self.id = id
        self.name = name
        self.primaryImageTag = primaryImageTag
        self.accessToken = accessToken
    }
}

/// A user the server lists on its sign-in screen.
public struct PublicUser: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let primaryImageTag: String?

    public init(id: String, name: String, primaryImageTag: String?) {
        self.id = id
        self.name = name
        self.primaryImageTag = primaryImageTag
    }
}

public enum AuthenticationError: Error, Equatable {
    /// The server rejected the username and password.
    case invalidCredentials
    /// The server answered without the user or token it should have sent.
    case unexpectedResponse
}

public enum QuickConnectProgress: Equatable, Sendable {
    /// Show this code. Someone approves it from a signed-in Jellyfin client.
    case code(String)
    case signedIn(SignedInUser)
}

/// Signs users in and out of a Jellyfin server, with a password or Quick Connect.
public struct Authenticator: Sendable {
    /// How long to wait for each request. Short enough that a launch with the server offline
    /// falls back quickly instead of sitting on URLSession's 60-second default.
    public static let timeout: TimeInterval = 10

    private let identity: ClientIdentity
    private let makeSessionConfiguration: @Sendable () -> URLSessionConfiguration

    public init(
        identity: ClientIdentity,
        sessionConfiguration: @escaping @Sendable () -> URLSessionConfiguration = { .default },
    ) {
        self.identity = identity
        makeSessionConfiguration = sessionConfiguration
    }

    /// The users shown on the server's sign-in screen. Admins can hide users from this list.
    public func publicUsers(on server: URL) async throws -> [PublicUser] {
        try await client(server).send(Paths.getPublicUsers).value.compactMap { user in
            guard let id = user.id, let name = user.name else { return nil }
            return PublicUser(id: id, name: name, primaryImageTag: user.primaryImageTag)
        }
    }

    public func signIn(to server: URL, username: String, password: String) async throws -> SignedInUser {
        do {
            return try await SignedInUser(client(server).signIn(username: username, password: password))
        } catch APIError.unacceptableStatusCode(401) {
            throw AuthenticationError.invalidCredentials
        }
    }

    public func isQuickConnectEnabled(on server: URL) async throws -> Bool {
        let data = try await client(server).send(Paths.getQuickConnectEnabled).value
        return String(bytes: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    /// Shows a code, waits for someone to approve it, then signs in. Cancel by dropping the stream.
    ///
    /// - Parameter pollInterval: seconds between approval checks.
    public func quickConnect(
        to server: URL,
        pollInterval: Int = 5,
    ) -> AsyncThrowingStream<QuickConnectProgress, any Error> {
        let client = client(server)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in client.quickConnect.connect(poll: pollInterval) {
                        switch event {
                        case let .polling(code):
                            continuation.yield(.code(code))
                        case let .authenticated(secret):
                            let result = try await client.signIn(quickConnectSecret: secret)
                            try continuation.yield(.signedIn(SignedInUser(result)))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The user `token` belongs to, or `nil` if the server no longer accepts it.
    public func currentUser(on server: URL, token: String) async throws -> SignedInUser? {
        do {
            let user = try await client(server, token: token).send(Paths.getCurrentUser).value
            guard let id = user.id, let name = user.name else { throw AuthenticationError.unexpectedResponse }
            return SignedInUser(id: id, name: name, primaryImageTag: user.primaryImageTag, accessToken: token)
        } catch APIError.unacceptableStatusCode(401) {
            return nil
        }
    }

    /// Ends the session on the server. Best effort: callers drop the token either way.
    ///
    /// Uses `/Sessions/Logout` rather than the SDK's `signOut()`, which revokes the key through
    /// an admin-only endpoint.
    public func signOut(from server: URL, token: String) async {
        _ = try? await client(server, token: token).send(Paths.reportSessionEnded)
    }

    private func client(_ server: URL, token: String? = nil) -> JellyfinClient {
        let configuration = makeSessionConfiguration()
        configuration.timeoutIntervalForRequest = Self.timeout
        return identity.makeClient(serverURL: server, accessToken: token, sessionConfiguration: configuration)
    }
}

private extension SignedInUser {
    init(_ result: AuthenticationResult) throws {
        guard let token = result.accessToken, let id = result.user?.id, let name = result.user?.name else {
            throw AuthenticationError.unexpectedResponse
        }
        self.init(id: id, name: name, primaryImageTag: result.user?.primaryImageTag, accessToken: token)
    }
}
