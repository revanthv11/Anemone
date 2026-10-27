#if ANEMONE_SEERR
    import AnemoneCore
    import Foundation

    /// The Seerr account a Jellyfin profile set up in Settings › Seerr, as Wholphin's `SeerrServer`
    /// and `SeerrUser` rows.
    ///
    /// Fixed while porting: Wholphin keeps the password and API key in plaintext in its database.
    /// Anemone keeps the whole account as one Keychain item per profile (`SeerrAccountStore`).
    public struct SeerrAccount: Codable, Hashable, Sendable {
        public enum Method: String, Codable, Hashable, Sendable, CaseIterable {
            /// The user's Jellyfin username and password, which Seerr checks with Jellyfin.
            case jellyfin
            /// A Seerr account of its own.
            case local
            case apiKey
        }

        /// The address that answered when the account was added.
        public var serverURL: URL
        public var method: Method
        public var username: String?
        /// The password, or the API key.
        public var secret: String

        public init(serverURL: URL, method: Method, username: String?, secret: String) {
            self.serverURL = serverURL
            self.method = method
            self.username = username
            self.secret = secret
        }

        public var credentials: SeerrCredentials {
            Self.credentials(method: method, username: username, secret: secret)
        }

        static func credentials(method: Method, username: String?, secret: String) -> SeerrCredentials {
            switch method {
            case .jellyfin: .jellyfin(username: username ?? "", password: secret)
            case .local: .local(username: username ?? "", password: secret)
            case .apiKey: .apiKey(secret)
            }
        }
    }

    extension SeerrAccount: CustomStringConvertible, CustomDebugStringConvertible {
        /// Never shows the password or API key.
        public var description: String {
            "SeerrAccount(serverURL: \(serverURL), method: \(method.rawValue))"
        }

        public var debugDescription: String {
            description
        }
    }

    /// Keeps each Jellyfin profile's Seerr account in a `SecureStore`, the Keychain in the app,
    /// since it holds a password or API key.
    public struct SeerrAccountStore: Sendable {
        private let store: any SecureStore

        public init(store: any SecureStore) {
            self.store = store
        }

        /// The account for the profile, or `nil` when it has none or it no longer reads.
        public func account(for profile: Profile) throws -> SeerrAccount? {
            guard let data = try store.data(for: profile.key) else { return nil }
            return try? JSONDecoder().decode(SeerrAccount.self, from: data)
        }

        /// Saves the account for the profile, or forgets it when `account` is `nil`.
        public func save(_ account: SeerrAccount?, for profile: Profile) throws {
            try store.set(account.map { try JSONEncoder().encode($0) }, for: profile.key)
        }

        /// A Jellyfin user on a Jellyfin server, whose Seerr account this is, as Wholphin keys
        /// Seerr users by Jellyfin user.
        public struct Profile: Hashable, Sendable {
            public var serverID: String
            public var userID: String

            public init(serverID: String, userID: String) {
                self.serverID = serverID
                self.userID = userID
            }

            var key: String {
                "seerr.\(serverID).\(userID)"
            }
        }
    }
#endif
