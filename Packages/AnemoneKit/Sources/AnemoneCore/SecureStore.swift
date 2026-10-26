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
public struct KeychainStore: SecureStore {
    public struct Failure: Error, Equatable {
        public let status: OSStatus
    }

    private let service: String

    public init(service: String) {
        self.service = service
    }

    public func data(for key: String) throws -> Data? {
        var query = baseQuery(for: key)
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
            throw Failure(status: status)
        }
    }

    public func set(_ data: Data?, for key: String) throws {
        let query = baseQuery(for: key)
        guard let data else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
            return
        }

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
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
    private static let key = "accounts"

    private let store: any SecureStore

    public init(store: any SecureStore) {
        self.store = store
    }

    /// The saved accounts, or a fresh store (with a new device ID) on first launch.
    public func load() throws -> AccountStore {
        guard let data = try store.data(for: Self.key) else { return AccountStore() }
        return try JSONDecoder().decode(AccountStore.self, from: data)
    }

    public func save(_ accounts: AccountStore) throws {
        try store.set(JSONEncoder().encode(accounts), for: Self.key)
    }
}
