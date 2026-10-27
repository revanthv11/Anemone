#if ANEMONE_SEERR
    import Foundation
    import OpenAPIRuntime

    /// A signed-in connection to a Seerr server: the user, what the server allows, and the
    /// requests Anemone makes. Ported from Wholphin's `SeerrApi`, `SeerrServerRepository` (signing
    /// in) and `SeerrService` (the requests).
    public struct SeerrConnection: Sendable {
        /// The server's own address, as the user reaches it in a browser.
        public let serverURL: URL
        public let user: SeerrUser
        public let settings: SeerrServerSettings
        let client: Client
        private let signing: SeerrSigning

        /// How long to wait for each request.
        public static let timeout: TimeInterval = 20

        /// Where the credentials to sign in again come from when Seerr's session goes, given the
        /// connection's server; `nil` when there are none for it any more.
        public typealias Renewal = @Sendable (_ serverURL: URL) async -> SeerrCredentials?

        /// Signs in to the Seerr server at `serverURL`, as Wholphin's `seerrLogin`: with a
        /// password, Seerr sets a session cookie that later requests send; with an API key, each
        /// request sends the key. Then reads the user and the server's public settings.
        ///
        /// - Parameters:
        ///   - configuration: the session's configuration; tests pass one with a fake server. It's
        ///     copied with its cookie handling turned off, since the session cookie is kept apart.
        ///   - renewal: the credentials to sign in again with, when Seerr's session goes (see
        ///     `SeerrSigning`). By default, `credentials`, kept in memory.
        /// - Throws: `SeerrError.invalidCredentials` when Seerr turns the sign-in down.
        public static func signIn(
            to serverURL: URL,
            with credentials: SeerrCredentials,
            configuration: URLSessionConfiguration = .ephemeral,
            renewal: Renewal? = nil,
        ) async throws -> SeerrConnection {
            // Kept by the connection and its sign-ins again; closed once the connection has gone.
            let transport = SeerrTransport(to: serverURL, configuration, timeout: timeout)
            let signing = SeerrSigning(apiKey: credentials.apiKey)
            let client = Client(serverURL: serverURL, signing: signing, transport: transport)
            try await logIn(client, with: credentials)
            let user: Components.Schemas.User
            switch try await client.getAuthMe() {
            case let .ok(response):
                user = try response.body.json
            case let .undocumented(status, _):
                throw SeerrError(signInStatus: status)
            }
            let settings = try await client.getSettingsPublic().ok.body.json
            let renewal = renewal ?? { _ in credentials }
            signing.renew { signing in
                await renew(Client(serverURL: serverURL, signing: signing, transport: transport)) {
                    await renewal(serverURL)
                }
            }
            return SeerrConnection(
                serverURL: serverURL,
                user: SeerrUser(user),
                settings: SeerrServerSettings(settings),
                client: client,
                signing: signing,
            )
        }

        /// Sends the username and password, for Seerr to set its session cookie. An API key needs
        /// no sign-in.
        private static func logIn(_ client: Client, with credentials: SeerrCredentials) async throws {
            switch credentials {
            case .apiKey:
                break
            case let .local(username, password):
                let output = try await client.postAuthLocal(body: .json(.init(email: username, password: password)))
                if case let .undocumented(status, _) = output {
                    throw SeerrError(signInStatus: status)
                }
            case let .jellyfin(username, password):
                let output = try await client.postAuthJellyfin(
                    body: .json(.init(username: username, password: password)),
                )
                if case let .undocumented(status, _) = output {
                    throw SeerrError(signInStatus: status)
                }
            }
        }

        /// Signs in again after Seerr turned a request down, unless the session still works. Only
        /// a password can: an API key Seerr turns down has stopped working.
        private static func renew(
            _ client: Client,
            with credentials: @Sendable () async -> SeerrCredentials?,
        ) async -> SeerrSigning.Renewal {
            do {
                switch try await client.getAuthMe() {
                case .ok:
                    return .stillSignedIn
                case let .undocumented(status, _) where status == 401 || status == 403:
                    break
                case .undocumented:
                    return .unknown
                }
                guard let credentials = await credentials(), credentials.apiKey == nil else {
                    return .signedOut
                }
                try await logIn(client, with: credentials)
                return .renewed
            } catch SeerrError.invalidCredentials {
                return .signedOut
            } catch {
                return .unknown
            }
        }

        /// Runs `action` once Seerr has signed this connection out for good: its session went and
        /// signing in again failed.
        public func onSignedOut(_ action: @escaping @Sendable () -> Void) {
            signing.onSignedOut(action)
        }

        /// Tries each address `SeerrAddress.candidates(for:)` makes of what the user typed, and
        /// signs in at the first Seerr server that answers, as Wholphin's add-server dialog does.
        ///
        /// Changed from Wholphin: each address is first checked with Seerr's public settings,
        /// which need no sign-in, so the password or API key is only sent to an address where a
        /// Seerr server answers, not to every guess.
        ///
        /// - Throws: `SeerrError.invalidAddress` when it isn't an address, the sign-in's error at
        ///   the server that answered, or `SeerrError.unexpectedResponse` when none did.
        public static func signIn(
            atAddress typed: String,
            with credentials: SeerrCredentials,
            configuration: @Sendable () -> URLSessionConfiguration = { .ephemeral },
            renewal: Renewal? = nil,
        ) async throws -> SeerrConnection {
            for url in try SeerrAddress.candidates(for: typed) where await isSeerr(at: url, configuration()) {
                return try await signIn(to: url, with: credentials, configuration: configuration(), renewal: renewal)
            }
            throw SeerrError.unexpectedResponse
        }

        /// Whether a Seerr server answers at `url`. Waits less than other requests, as Wholphin's
        /// `testConnection` does, since most guessed addresses don't answer. Its session closes
        /// as soon as the answer is in.
        static func isSeerr(at url: URL, _ configuration: URLSessionConfiguration) async -> Bool {
            let client = Client(
                serverURL: url,
                signing: SeerrSigning(apiKey: nil),
                transport: SeerrTransport(to: url, configuration, timeout: 6),
            )
            do {
                _ = try await client.getSettingsPublic().ok.body.json
                return true
            } catch {
                return false
            }
        }

        init(serverURL: URL, user: SeerrUser, settings: SeerrServerSettings, client: Client, signing: SeerrSigning) {
            self.serverURL = serverURL
            self.user = user
            self.settings = settings
            self.client = client
            self.signing = signing
        }

        // MARK: What the user may do

        /// Whether the user may request movies, and in 4K, as Wholphin's `CurrentSeerr`.
        public var canRequestMovies: Bool {
            user.permissions.contains(.requestMovie)
        }

        public var canRequest4KMovies: Bool {
            settings.allows4KMovies && user.permissions.contains(.request4KMovie)
        }

        public var canRequestSeries: Bool {
            user.permissions.contains(.requestTV)
        }

        public var canRequest4KSeries: Bool {
            settings.allows4KSeries && user.permissions.contains(.request4KTV)
        }
    }
#endif
