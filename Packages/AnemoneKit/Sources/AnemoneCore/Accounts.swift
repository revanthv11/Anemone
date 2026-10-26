import Foundation

/// A Jellyfin server saved on this Apple TV.
public struct SavedServer: Codable, Hashable, Identifiable, Sendable {
    /// The server's own ID, from `/System/Info/Public`.
    public let id: String
    public var name: String
    public var url: URL
    public var version: String
    public var lastUsed: Date

    public init(id: String, name: String, url: URL, version: String, lastUsed: Date = .now) {
        self.id = id
        self.name = name
        self.url = url
        self.version = version
        self.lastUsed = lastUsed
    }
}

/// A user who has signed in on this Apple TV.
public struct SavedUser: Codable, Hashable, Identifiable, Sendable {
    /// The Jellyfin user ID.
    public let id: String
    public let serverID: SavedServer.ID
    public var name: String
    public var primaryImageTag: String?
    /// `nil` after signing out: the profile stays on the list but must sign in again.
    public var accessToken: String?
    public var lock: ProfileLock
    public var lastUsed: Date

    public init(
        id: String,
        serverID: SavedServer.ID,
        name: String,
        primaryImageTag: String? = nil,
        accessToken: String?,
        lock: ProfileLock = .unlocked,
        lastUsed: Date = .now,
    ) {
        self.id = id
        self.serverID = serverID
        self.name = name
        self.primaryImageTag = primaryImageTag
        self.accessToken = accessToken
        self.lock = lock
        self.lastUsed = lastUsed
    }
}

/// What it takes to switch to a profile, like Wholphin's PIN / "require login" options.
public enum ProfileLock: Codable, Hashable, Sendable {
    case unlocked
    case pin(PINHash)
    /// Always sign in again (password or Quick Connect) when switching to this profile.
    case requireSignIn
}

/// Everything Anemone keeps about servers and users.
///
/// It is stored as a single Keychain item, because tvOS may purge any other local storage.
public struct AccountStore: Codable, Hashable, Sendable {
    public struct Session: Codable, Hashable, Sendable {
        public let serverID: SavedServer.ID
        public let userID: SavedUser.ID

        public init(serverID: SavedServer.ID, userID: SavedUser.ID) {
            self.serverID = serverID
            self.userID = userID
        }
    }

    /// Sent to servers so they can tell this Apple TV's sessions and tokens apart.
    public let deviceID: String
    public private(set) var servers: [SavedServer] = []
    public private(set) var users: [SavedUser] = []
    /// The profile to restore on launch.
    public var lastSession: Session?

    public init(deviceID: String = UUID().uuidString) {
        self.deviceID = deviceID
    }

    public var serversByRecentUse: [SavedServer] {
        servers.sorted { $0.lastUsed > $1.lastUsed }
    }

    public func users(on serverID: SavedServer.ID) -> [SavedUser] {
        users.filter { $0.serverID == serverID }.sorted { $0.lastUsed > $1.lastUsed }
    }

    public func server(id: SavedServer.ID) -> SavedServer? {
        servers.first { $0.id == id }
    }

    public func user(id: SavedUser.ID, on serverID: SavedServer.ID) -> SavedUser? {
        users.first { $0.id == id && $0.serverID == serverID }
    }

    /// Adds the server, or replaces the saved one with the same ID (e.g. after its address changed).
    public mutating func save(_ server: SavedServer) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
        } else {
            servers.append(server)
        }
    }

    /// Adds the user, or replaces the saved one with the same ID on the same server.
    public mutating func save(_ user: SavedUser) {
        if let index = users.firstIndex(where: { $0.id == user.id && $0.serverID == user.serverID }) {
            users[index] = user
        } else {
            users.append(user)
        }
    }

    /// Forgets the server and every user saved for it.
    public mutating func removeServer(id: SavedServer.ID) {
        servers.removeAll { $0.id == id }
        users.removeAll { $0.serverID == id }
        if lastSession?.serverID == id {
            lastSession = nil
        }
    }

    public mutating func removeUser(id: SavedUser.ID, on serverID: SavedServer.ID) {
        users.removeAll { $0.id == id && $0.serverID == serverID }
        if lastSession == Session(serverID: serverID, userID: id) {
            lastSession = nil
        }
    }

    /// Drops the user's access token but keeps the profile, so it can sign in again.
    public mutating func signOut(userID: SavedUser.ID, on serverID: SavedServer.ID) {
        guard var user = user(id: userID, on: serverID) else { return }
        user.accessToken = nil
        save(user)
        if lastSession == Session(serverID: serverID, userID: userID) {
            lastSession = nil
        }
    }
}
