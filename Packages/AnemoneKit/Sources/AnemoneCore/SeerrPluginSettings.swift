#if ANEMONE_SEERR
    import Foundation

    /// The Seerr server the companion plugin sets up for every user of a Jellyfin server, from its
    /// `GET /wholphin/seerrsettings`. Ported from Wholphin's `SeerrPluginSettings` at `cecfdae`.
    ///
    /// It lives here rather than in AnemoneJellyfin, which fetches it, so AnemoneSeerr can log in
    /// with it without depending on the Jellyfin client.
    ///
    /// The login it carries is a shared credential the admin typed into the plugin. Anemone keeps
    /// it in memory only, never in the Keychain, UserDefaults or logs, so `description` hides it.
    public struct SeerrPluginSettings: Equatable, Sendable {
        /// How the plugin says to sign in to Seerr.
        public enum Login: Equatable, Sendable {
            /// The plugin pushes only the address; the user signs in themselves.
            case none
            case apiKey(String)
            /// A local Seerr account shared by everyone on the Jellyfin server.
            case local(username: String, password: String)
        }

        public var version: Int
        /// The Seerr server's address, as the admin typed it. `nil` when the plugin sets none.
        public var serverURL: String?
        public var login: Login

        public init(version: Int = 1, serverURL: String?, login: Login = .none) {
            self.version = version
            self.serverURL = serverURL
            self.login = login
        }

        /// The address, unless it's blank.
        public var address: String? {
            guard let serverURL = serverURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !serverURL.isEmpty
            else { return nil }
            return serverURL
        }

        /// Whether the plugin gives both an address and a way to sign in, so Anemone can sign in
        /// without asking, as Wholphin's `usePluginProvidedServer` requires.
        public var canSignIn: Bool {
            address != nil && login != .none
        }
    }

    extension SeerrPluginSettings: Decodable {
        private enum CodingKeys: String, CodingKey {
            case version
            case serverURL = "serverUrl"
            case login
        }

        private struct RawLogin: Decodable {
            let type: String?
            let apiKey: String?
            let local: RawLocalLogin?
        }

        private struct RawLocalLogin: Decodable {
            let username: String?
            let password: String?
        }

        /// Read leniently. The plugin writes every property, `null` included, and its `login` is
        /// tagged by `type` (`None`, `ApiKey` or `Local`). A login of an unknown type, or one missing
        /// its credentials, counts as none, so the address still reaches the add-server page:
        /// Wholphin's sealed type throws on those and loses the address too.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
            serverURL = try container.decodeIfPresent(String.self, forKey: .serverURL)
            let raw = try? container.decodeIfPresent(RawLogin.self, forKey: .login)
            login = Self.login(from: raw)
        }

        private static func login(from raw: RawLogin?) -> Login {
            switch raw?.type {
            case "ApiKey":
                guard let key = raw?.apiKey, !key.isEmpty else { return .none }
                return .apiKey(key)
            case "Local":
                guard let username = raw?.local?.username, !username.isEmpty,
                      let password = raw?.local?.password
                else { return .none }
                return .local(username: username, password: password)
            default:
                return .none
            }
        }
    }

    extension SeerrPluginSettings: CustomStringConvertible, CustomDebugStringConvertible {
        /// Names the login's kind but never its credentials.
        public var description: String {
            let kind = switch login {
            case .none: "none"
            case .apiKey: "API key"
            case .local: "local account"
            }
            return "SeerrPluginSettings(serverURL: \(serverURL ?? "nil"), login: \(kind))"
        }

        public var debugDescription: String {
            description
        }
    }

    extension SeerrPluginSettings.Login: CustomStringConvertible, CustomDebugStringConvertible {
        public var description: String {
            switch self {
            case .none: "none"
            case .apiKey: "apiKey(<hidden>)"
            case .local: "local(<hidden>)"
            }
        }

        public var debugDescription: String {
            description
        }
    }
#endif
