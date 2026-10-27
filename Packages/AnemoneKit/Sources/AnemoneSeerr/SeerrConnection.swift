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

        /// How long to wait for each request.
        public static let timeout: TimeInterval = 20

        /// Signs in to the Seerr server at `serverURL`, as Wholphin's `seerrLogin`: with a
        /// password, Seerr sets a session cookie that later requests send; with an API key, each
        /// request sends the key. Then reads the user and the server's public settings.
        ///
        /// - Parameter configuration: the session's configuration; tests pass one with a fake
        ///   server. Its cookie handling is turned off, since the session cookie is kept apart.
        /// - Throws: `SeerrError.invalidCredentials` when Seerr turns the sign-in down.
        public static func signIn(
            to serverURL: URL,
            with credentials: SeerrCredentials,
            configuration: URLSessionConfiguration = .ephemeral,
        ) async throws -> SeerrConnection {
            if configuration.timeoutIntervalForRequest > timeout {
                configuration.timeoutIntervalForRequest = timeout
            }
            let client = Client(
                serverURL: serverURL,
                signing: SeerrSigning(apiKey: credentials.apiKey),
                configuration: configuration,
            )
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
            let user: Components.Schemas.User
            switch try await client.getAuthMe() {
            case let .ok(response):
                user = try response.body.json
            case let .undocumented(status, _):
                throw SeerrError(signInStatus: status)
            }
            let settings = try await client.getSettingsPublic().ok.body.json
            return SeerrConnection(
                serverURL: serverURL,
                user: SeerrUser(user),
                settings: SeerrServerSettings(settings),
                client: client,
            )
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
        ) async throws -> SeerrConnection {
            for url in try SeerrAddress.candidates(for: typed) where await isSeerr(at: url, configuration()) {
                return try await signIn(to: url, with: credentials, configuration: configuration())
            }
            throw SeerrError.unexpectedResponse
        }

        /// Whether a Seerr server answers at `url`. Waits less than other requests, as Wholphin's
        /// `testConnection` does, since most guessed addresses don't answer.
        static func isSeerr(at url: URL, _ configuration: URLSessionConfiguration) async -> Bool {
            configuration.timeoutIntervalForRequest = 6
            let client = Client(serverURL: url, signing: SeerrSigning(apiKey: nil), configuration: configuration)
            do {
                _ = try await client.getSettingsPublic().ok.body.json
                return true
            } catch {
                return false
            }
        }

        init(serverURL: URL, user: SeerrUser, settings: SeerrServerSettings, client: Client) {
            self.serverURL = serverURL
            self.user = user
            self.settings = settings
            self.client = client
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
