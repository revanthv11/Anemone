import Foundation
import Security
import Synchronization

/// Small, persistent key-value storage for secrets.
public protocol SecureStore: Sendable {
    func data(for key: String) throws -> Data?
    /// Stores `data`, or deletes the key when `data` is `nil`.
    func set(_ data: Data?, for key: String) throws
}

/// Generic-password Keychain items. On tvOS this is the only local storage the system won't purge.
///
/// With an access group, the items live in that group, which the app shares with its Top Shelf
/// extension. A build without the group's entitlement, such as an unsigned one, keeps them in its
/// own default group instead.
public struct KeychainStore: SecureStore {
    public struct Failure: Error, Equatable {
        public let status: OSStatus

        /// The app isn't entitled to the access group it asked for.
        var isMissingEntitlement: Bool {
            status == errSecMissingEntitlement
        }
    }

    private let service: String
    private let accessGroup: String?
    private let keychain: any KeychainItems

    public init(service: String, accessGroup: String? = nil) {
        self.init(service: service, accessGroup: accessGroup, keychain: SystemKeychain())
    }

    init(service: String, accessGroup: String? = nil, keychain: any KeychainItems) {
        self.service = service
        self.accessGroup = accessGroup
        self.keychain = keychain
    }

    public func data(for key: String) throws -> Data? {
        try inAccessGroup { group in
            try keychain.data(service: service, account: key, accessGroup: group)
        }
    }

    public func set(_ data: Data?, for key: String) throws {
        try inAccessGroup { group in
            if let data {
                try keychain.save(data, service: service, account: key, accessGroup: group)
            } else {
                try keychain.delete(service: service, account: key, accessGroup: group)
            }
        }
    }

    /// Runs `work` in the store's access group, or in the app's own groups when the app turns out
    /// not to be entitled to it.
    private func inAccessGroup<Value>(_ work: (String?) throws -> Value) throws -> Value {
        guard let accessGroup else { return try work(nil) }
        do {
            return try work(accessGroup)
        } catch let failure as Failure where failure.isMissingEntitlement {
            return try work(nil)
        }
    }
}

// MARK: Moving into the shared access group

public extension KeychainStore {
    enum MoveOutcome: Equatable, Sendable {
        /// Every item was already in the group, or there were none.
        case nothingToMove
        /// This many items were copied into the group.
        case moved(Int)
        /// The group couldn't be written, so the items stayed where they were.
        case groupUnavailable(OSStatus)
    }

    /// Moves the service's items from the app's other access groups into `accessGroup`, so an app
    /// update that starts sharing them with an extension keeps the sign-ins saved before it.
    ///
    /// Each item is copied into the group before the old one is deleted, so nothing is lost if
    /// the group can't be written; the items then stay where they were, and the outcome says so.
    /// A copy already in the group wins over an old one, which is just deleted.
    @discardableResult
    static func moveItems(service: String, into accessGroup: String) -> MoveOutcome {
        moveItems(service: service, into: accessGroup, keychain: SystemKeychain())
    }

    internal static func moveItems(
        service: String,
        into accessGroup: String,
        keychain: any KeychainItems,
    ) -> MoveOutcome {
        let entries: [KeychainEntry]
        do {
            entries = try keychain.entries(service: service)
        } catch let failure as Failure {
            return .groupUnavailable(failure.status)
        } catch {
            return .groupUnavailable(errSecInternalError)
        }
        var inGroup = Set(entries.filter { $0.accessGroup == accessGroup }.map(\.account))
        var moved = 0
        for entry in entries where entry.accessGroup != accessGroup {
            if !inGroup.contains(entry.account) {
                do {
                    guard let data = try keychain.data(
                        service: service,
                        account: entry.account,
                        accessGroup: entry.accessGroup,
                    ) else { continue }
                    try keychain.save(data, service: service, account: entry.account, accessGroup: accessGroup)
                } catch {
                    return .groupUnavailable((error as? Failure)?.status ?? errSecInternalError)
                }
                inGroup.insert(entry.account)
                moved += 1
            }
            // A copy that can't be deleted is left behind; the group's copy is the one read.
            try? keychain.delete(service: service, account: entry.account, accessGroup: entry.accessGroup)
        }
        return moved > 0 ? .moved(moved) : .nothingToMove
    }
}

/// One generic-password item: its account (the key) and the access group it lives in.
struct KeychainEntry: Hashable, Sendable {
    let account: String
    let accessGroup: String
}

/// The Keychain calls `KeychainStore` makes, so tests can stand in for the Keychain. `nil` for
/// an access group means any of the app's groups when reading, and its default when writing.
protocol KeychainItems: Sendable {
    /// Every item of the service, in any of the app's access groups.
    func entries(service: String) throws -> [KeychainEntry]
    func data(service: String, account: String, accessGroup: String?) throws -> Data?
    /// Replaces the item's data, or adds the item.
    func save(_ data: Data, service: String, account: String, accessGroup: String?) throws
    /// Deletes the item if it exists.
    func delete(service: String, account: String, accessGroup: String?) throws
}

/// The real Keychain.
struct SystemKeychain: KeychainItems {
    func entries(service: String) throws -> [KeychainEntry] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            let items = result as? [[String: Any]] ?? []
            return items.compactMap { attributes in
                guard let account = attributes[kSecAttrAccount as String] as? String,
                      let group = attributes[kSecAttrAccessGroup as String] as? String
                else { return nil }
                return KeychainEntry(account: account, accessGroup: group)
            }
        case errSecItemNotFound:
            return []
        default:
            throw KeychainStore.Failure(status: status)
        }
    }

    func data(service: String, account: String, accessGroup: String?) throws -> Data? {
        var query = Self.query(service: service, account: account, accessGroup: accessGroup)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainStore.Failure(status: status)
        }
    }

    func save(_ data: Data, service: String, account: String, accessGroup: String?) throws {
        let query = Self.query(service: service, account: account, accessGroup: accessGroup)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainStore.Failure(status: status) }
    }

    func delete(service: String, account: String, accessGroup: String?) throws {
        let query = Self.query(service: service, account: account, accessGroup: accessGroup)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStore.Failure(status: status)
        }
    }

    private static func query(service: String, account: String, accessGroup: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}

/// For tests and previews.
public final class InMemorySecureStore: SecureStore {
    private let values = Mutex<[String: Data]>([:])

    public init() {}

    public func data(for key: String) throws -> Data? {
        values.withLock { $0[key] }
    }

    public func set(_ data: Data?, for key: String) throws {
        values.withLock { $0[key] = data }
    }
}

/// Loads and saves the `AccountStore` as one JSON item in a `SecureStore`.
public struct AccountRepository: Sendable {
    static let key = "accounts"
    /// Where an item that no longer decodes is kept, so the next save can't destroy it.
    static let unreadableKey = "accounts.unreadable"

    private let store: any SecureStore

    public init(store: any SecureStore) {
        self.store = store
    }

    /// The saved accounts, or a fresh store (with a new device ID) on first launch.
    ///
    /// If the saved item no longer decodes (say, after a format change), it's set aside under
    /// `unreadableKey` and a fresh store is returned that keeps the old device ID where possible.
    ///
    /// - Throws: when the store itself can't be read. Callers must not save over the item then.
    public func load() throws -> AccountStore {
        guard let data = try store.data(for: Self.key) else { return AccountStore() }
        do {
            return try JSONDecoder().decode(AccountStore.self, from: data)
        } catch {
            if try store.data(for: Self.unreadableKey) == nil {
                try store.set(data, for: Self.unreadableKey)
            }
            let deviceID = try? JSONDecoder().decode(DeviceIDOnly.self, from: data).deviceID
            return AccountStore(deviceID: deviceID ?? UUID().uuidString)
        }
    }

    /// The saved accounts as they are, for readers that must not change them, such as the Top
    /// Shelf: `nil` when there are none, or the item can't be read or no longer decodes.
    public func loadReadOnly() -> AccountStore? {
        guard let data = try? store.data(for: Self.key) else { return nil }
        return try? JSONDecoder().decode(AccountStore.self, from: data)
    }

    public func save(_ accounts: AccountStore) throws {
        try store.set(JSONEncoder().encode(accounts), for: Self.key)
    }

    private struct DeviceIDOnly: Decodable {
        let deviceID: String
    }
}
