import AnemoneCore
import AnemoneJellyfin
import Observation
import UIKit

/// Drives server setup, sign-in, profile switching and session restore, like Wholphin's
/// setup navigation (server list → user list → app).
@Observable
final class AppModel {
    enum Screen: Equatable {
        case loading
        case servers
        case users(SavedServer)
        case home(SavedServer, SavedUser)
    }

    enum SwitchOutcome {
        case signedIn
        case needsPIN
        case needsSignIn
        /// The server didn't answer; `notice` says so.
        case unreachable
    }

    private(set) var screen = Screen.loading
    private(set) var accounts: AccountStore
    /// One line for the current screen, such as why a saved session couldn't be restored.
    var notice: String?

    let authenticator: Authenticator
    let connector: ServerConnector
    private let repository: AccountRepository

    init(repository: AccountRepository = AccountRepository(store: KeychainStore(service: "com.revanthv11.anemone"))) {
        self.repository = repository
        #if DEBUG
            // UI tests start from a clean slate with `-resetAccounts YES`.
            if UserDefaults.standard.bool(forKey: "resetAccounts") {
                try? repository.save(AccountStore())
            }
        #endif
        let accounts = (try? repository.load()) ?? AccountStore()
        self.accounts = accounts

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let identity = ClientIdentity(
            deviceName: UIDevice.current.name,
            deviceID: accounts.deviceID,
            appVersion: version,
        )
        authenticator = Authenticator(identity: identity)
        connector = ServerConnector(identity: identity)
    }

    /// Restores the last profile if it isn't locked and its token still works; otherwise shows
    /// the user list for the last server, or the server list.
    func start() async {
        guard let session = accounts.lastSession, let server = accounts.server(id: session.serverID) else {
            screen = .servers
            return
        }
        guard let user = accounts.user(id: session.userID, on: server.id), user.lock == .unlocked else {
            screen = .users(server)
            return
        }
        if await resume(user, on: server) == .unreachable {
            screen = .servers
        }
    }

    // MARK: Servers

    func addServer(address: String) async throws(ServerConnectionError) {
        let connected = try await connector.connect(to: address)
        let server = SavedServer(id: connected.id, name: connected.name, url: connected.url, version: connected.version)
        accounts.save(server)
        persist()
        showUsers(on: server)
    }

    func removeServer(_ server: SavedServer) {
        accounts.removeServer(id: server.id)
        persist()
    }

    func showServers() {
        notice = nil
        screen = .servers
    }

    func showUsers(on server: SavedServer) {
        notice = nil
        screen = .users(server)
    }

    // MARK: Signing in

    func signIn(to server: SavedServer, username: String, password: String) async throws {
        let user = try await authenticator.signIn(to: server.url, username: username, password: password)
        enterHome(server: server, user: user)
    }

    /// Called when Quick Connect finishes.
    func finishSignIn(to server: SavedServer, as user: SignedInUser) {
        enterHome(server: server, user: user)
    }

    /// Switches to a profile saved on this Apple TV, if its lock allows it.
    func switchTo(_ user: SavedUser, on server: SavedServer) async -> SwitchOutcome {
        switch user.lock {
        case .unlocked:
            await resume(user, on: server)
        case .pin:
            .needsPIN
        case .requireSignIn:
            .needsSignIn
        }
    }

    /// Switches to a PIN-locked profile. Returns `nil` when the PIN is wrong.
    func unlock(_ user: SavedUser, on server: SavedServer, pin: String) async -> SwitchOutcome? {
        guard case let .pin(hash) = user.lock, hash.matches(pin) else { return nil }
        return await resume(user, on: server)
    }

    // MARK: Signed in

    /// Back to the profile list. The current profile stays signed in.
    func switchUser() {
        guard case let .home(server, _) = screen else { return }
        showUsers(on: server)
    }

    func signOut() async {
        guard case let .home(server, user) = screen else { return }
        if let token = user.accessToken {
            await authenticator.signOut(from: server.url, token: token)
        }
        accounts.signOut(userID: user.id, on: server.id)
        persist()
        showUsers(on: server)
    }

    /// Removes a profile from this Apple TV, signing it out on the server first.
    func forget(_ user: SavedUser, on server: SavedServer) async {
        if let token = user.accessToken {
            await authenticator.signOut(from: server.url, token: token)
        }
        accounts.removeUser(id: user.id, on: server.id)
        persist()
    }

    func setLock(_ lock: ProfileLock) {
        guard case let .home(server, user) = screen, var saved = accounts.user(id: user.id, on: server.id) else {
            return
        }
        saved.lock = lock
        accounts.save(saved)
        persist()
        screen = .home(server, saved)
    }

    // MARK: Private

    private func resume(_ user: SavedUser, on server: SavedServer) async -> SwitchOutcome {
        guard let token = user.accessToken else { return .needsSignIn }
        do {
            guard let current = try await authenticator.currentUser(on: server.url, token: token) else {
                accounts.signOut(userID: user.id, on: server.id)
                persist()
                notice = "\(user.name) was signed out by the server. Sign in again."
                screen = .users(server)
                return .needsSignIn
            }
            enterHome(server: server, user: current)
            return .signedIn
        } catch {
            notice = "Couldn't reach \(server.name)."
            return .unreachable
        }
    }

    private func enterHome(server: SavedServer, user: SignedInUser) {
        var server = server
        server.lastUsed = .now
        var saved = accounts.user(id: user.id, on: server.id)
            ?? SavedUser(id: user.id, serverID: server.id, name: user.name, accessToken: nil)
        saved.name = user.name
        saved.primaryImageTag = user.primaryImageTag
        saved.accessToken = user.accessToken
        saved.lastUsed = .now

        accounts.save(server)
        accounts.save(saved)
        accounts.lastSession = .init(serverID: server.id, userID: saved.id)
        persist()
        notice = nil
        screen = .home(server, saved)
    }

    private func persist() {
        do {
            try repository.save(accounts)
        } catch {
            notice = "Couldn't save your sign-in on this Apple TV."
        }
    }
}

extension ServerConnectionError {
    var message: String {
        switch self {
        case .invalidAddress:
            "That doesn't look like a server address."
        case .unreachable:
            "Couldn't find a Jellyfin server at that address."
        case let .unsupportedVersion(version):
            "This server runs Jellyfin \(version). " +
                "Anemone needs Jellyfin \(ServerVersion.minimumSupported.major) or later."
        case .setupIncomplete:
            "This server hasn't finished its setup. Finish it in a web browser first."
        }
    }
}
