#if ANEMONE_SEERR
    import AnemoneCore
    import Foundation

    /// Where a profile's Seerr connection stands.
    public enum SeerrStatus: Sendable {
        /// No Seerr server is set up. `suggestedAddress` is the companion plugin's address, for
        /// the add-server page to fill in, when the plugin gives one without a way to sign in.
        case notConfigured(suggestedAddress: String?)
        /// `isManagedByServer` when the companion plugin set it up; it can't be removed then.
        case connected(SeerrConnection, isManagedByServer: Bool)
        case failed(SeerrFailure)

        public var connection: SeerrConnection? {
            if case let .connected(connection, _) = self {
                return connection
            }
            return nil
        }
    }

    /// A Seerr server that's set up but couldn't be signed in to.
    public struct SeerrFailure: Sendable {
        public var address: String
        public var error: any Error
        /// When the companion plugin set it up: Settings offers Retry instead of Remove.
        public var isManagedByServer: Bool

        public init(address: String, error: any Error, isManagedByServer: Bool) {
            self.address = address
            self.error = error
            self.isManagedByServer = isManagedByServer
        }
    }

    /// Signs a Jellyfin profile in to its Seerr server: the one the companion plugin sets up for
    /// everyone, or the one the profile added in Settings › Seerr. Ported from the Seerr part of
    /// Wholphin's `UserSwitchListener` and `SeerrServerRepository.usePluginProvidedServer` at
    /// `cecfdae`.
    ///
    /// The plugin's login stays in memory: nothing about it is saved, so a change in the plugin
    /// shows up the next time the profile signs in, as in Wholphin.
    public struct SeerrSignIn: Sendable {
        let accounts: SeerrAccountStore
        let profile: SeerrAccountStore.Profile
        let configuration: @Sendable () -> URLSessionConfiguration

        public init(
            accounts: SeerrAccountStore,
            profile: SeerrAccountStore.Profile,
            configuration: @escaping @Sendable () -> URLSessionConfiguration = { .ephemeral },
        ) {
            self.accounts = accounts
            self.profile = profile
            self.configuration = configuration
        }

        /// Signs in with the plugin's server first, then with the profile's own account.
        ///
        /// Fixed while porting, from three quirks in Wholphin's version:
        /// - any failure to read the plugin's settings falls through to the profile's account,
        ///   where Wholphin's job stops on an error;
        /// - when the plugin's sign-in fails but the profile's own account works, the connection
        ///   isn't marked as managed by the server, so it can still be removed;
        /// - nothing here holds up the add-server page (see `suggestedAddress`).
        ///
        /// - Parameter pluginSettings: reads the plugin's settings; `nil` when it has none.
        public func connect(pluginSettings: @Sendable () async throws -> SeerrPluginSettings?) async -> SeerrStatus {
            let settings = try? await pluginSettings()
            var pluginFailure: SeerrFailure?
            if let settings, settings.canSignIn, let address = settings.address,
               let credentials = settings.login.credentials
            {
                do {
                    let connection = try await SeerrConnection.signIn(
                        atAddress: address,
                        with: credentials,
                        configuration: configuration,
                    )
                    return .connected(connection, isManagedByServer: true)
                } catch {
                    pluginFailure = SeerrFailure(address: address, error: error, isManagedByServer: true)
                }
            }
            guard let account = (try? accounts.account(for: profile)) ?? nil else {
                if let pluginFailure {
                    return .failed(pluginFailure)
                }
                return .notConfigured(suggestedAddress: settings?.address)
            }
            do {
                let connection = try await SeerrConnection.signIn(
                    to: account.serverURL,
                    with: account.credentials,
                    configuration: configuration(),
                    renewal: savedCredentials,
                )
                return .connected(connection, isManagedByServer: false)
            } catch {
                return .failed(
                    SeerrFailure(address: account.serverURL.absoluteString, error: error, isManagedByServer: false),
                )
            }
        }

        /// Signs in to the server at what the user typed and saves it as the profile's account,
        /// as Wholphin's add-server dialog: the password or API key goes in the Keychain.
        public func add(address: String, method: SeerrAccount.Method, username: String?, secret: String) async throws
            -> SeerrConnection
        {
            let username = method == .apiKey ? nil : username
            let connection = try await SeerrConnection.signIn(
                atAddress: address,
                with: SeerrAccount.credentials(method: method, username: username, secret: secret),
                configuration: configuration,
                renewal: savedCredentials,
            )
            let account = SeerrAccount(
                serverURL: connection.serverURL,
                method: method,
                username: username,
                secret: secret,
            )
            try accounts.save(account, for: profile)
            return connection
        }

        /// Forgets the profile's own account, as Wholphin's `removeServerForCurrentUser`.
        public func remove() throws {
            try accounts.save(nil, for: profile)
        }

        /// The profile's own account's password or API key, read from the Keychain again each time
        /// its connection signs in again, so it isn't kept in memory; none once the account is
        /// for another server or gone. The plugin's login signs in again from memory instead.
        private var savedCredentials: SeerrConnection.Renewal {
            { [accounts, profile] serverURL in
                guard let account = (try? accounts.account(for: profile)) ?? nil, account.serverURL == serverURL else {
                    return nil
                }
                return account.credentials
            }
        }
    }

    extension SeerrPluginSettings.Login {
        var credentials: SeerrCredentials? {
            switch self {
            case .none: nil
            case let .apiKey(key): .apiKey(key)
            case let .local(username, password): .local(username: username, password: password)
            }
        }
    }
#endif
