@testable import AnemoneCore
import Foundation
import Security
import Synchronization
import Testing

struct KeychainStoreTests {
    private let service = "com.revanthv11.anemone"
    private let appGroup = "TEAM.com.revanthv11.anemone"
    private let sharedGroup = "TEAM.com.revanthv11.anemone.shared"

    @Test func `moves the saved sign-ins into the shared group`() throws {
        let keychain = FakeKeychain(groups: [sharedGroup, appGroup])
        keychain.put(Data("accounts".utf8), account: "accounts", group: appGroup)

        let outcome = KeychainStore.moveItems(service: service, into: sharedGroup, keychain: keychain)

        #expect(outcome == .moved(1))
        #expect(keychain.items == [FakeKeychain.Key(account: "accounts", group: sharedGroup): Data("accounts".utf8)])
        let store = KeychainStore(service: service, accessGroup: sharedGroup, keychain: keychain)
        #expect(try store.data(for: "accounts") == Data("accounts".utf8))
    }

    @Test func `moves every item of the service, including one set aside`() {
        let keychain = FakeKeychain(groups: [sharedGroup, appGroup])
        keychain.put(Data("a".utf8), account: "accounts", group: appGroup)
        keychain.put(Data("b".utf8), account: "accounts.unreadable", group: appGroup)
        keychain.put(Data("c".utf8), account: "other", group: appGroup, service: "someone.else")

        #expect(KeychainStore.moveItems(service: service, into: sharedGroup, keychain: keychain) == .moved(2))
        #expect(keychain.items[.init(account: "accounts", group: sharedGroup)] == Data("a".utf8))
        #expect(keychain.items[.init(account: "accounts.unreadable", group: sharedGroup)] == Data("b".utf8))
        #expect(keychain.items[.init(account: "other", group: appGroup, service: "someone.else")] == Data("c".utf8))
    }

    @Test func `leaves items already in the shared group alone`() {
        let keychain = FakeKeychain(groups: [sharedGroup, appGroup])
        keychain.put(Data("new".utf8), account: "accounts", group: sharedGroup)

        #expect(KeychainStore.moveItems(service: service, into: sharedGroup, keychain: keychain) == .nothingToMove)
        #expect(keychain.items == [.init(account: "accounts", group: sharedGroup): Data("new".utf8)])
    }

    @Test func `a copy already in the shared group wins over an old one`() {
        let keychain = FakeKeychain(groups: [sharedGroup, appGroup])
        keychain.put(Data("old".utf8), account: "accounts", group: appGroup)
        keychain.put(Data("new".utf8), account: "accounts", group: sharedGroup)

        #expect(KeychainStore.moveItems(service: service, into: sharedGroup, keychain: keychain) == .nothingToMove)
        #expect(keychain.items == [.init(account: "accounts", group: sharedGroup): Data("new".utf8)])
    }

    @Test func `keeps the old item when the shared group can't be written`() throws {
        // A build without the Keychain Sharing entitlement.
        let keychain = FakeKeychain(groups: [appGroup])
        keychain.put(Data("accounts".utf8), account: "accounts", group: appGroup)

        let outcome = KeychainStore.moveItems(service: service, into: sharedGroup, keychain: keychain)

        #expect(outcome == .groupUnavailable(errSecMissingEntitlement))
        #expect(keychain.items == [.init(account: "accounts", group: appGroup): Data("accounts".utf8)])
        let store = KeychainStore(service: service, keychain: keychain)
        #expect(try store.data(for: "accounts") == Data("accounts".utf8))
    }

    @Test func `a store without the group's entitlement uses the app's own group`() throws {
        let keychain = FakeKeychain(groups: [appGroup])
        let store = KeychainStore(service: service, accessGroup: sharedGroup, keychain: keychain)

        try store.set(Data("saved".utf8), for: "accounts")

        #expect(keychain.items == [.init(account: "accounts", group: appGroup): Data("saved".utf8)])
        #expect(try store.data(for: "accounts") == Data("saved".utf8))
        try store.set(nil, for: "accounts")
        #expect(keychain.items.isEmpty)
    }

    @Test func `a store with a group reads and writes only that group`() throws {
        let keychain = FakeKeychain(groups: [sharedGroup, appGroup])
        keychain.put(Data("old".utf8), account: "accounts", group: appGroup)
        let store = KeychainStore(service: service, accessGroup: sharedGroup, keychain: keychain)

        #expect(try store.data(for: "accounts") == nil)
        try store.set(Data("new".utf8), for: "accounts")

        #expect(keychain.items[.init(account: "accounts", group: sharedGroup)] == Data("new".utf8))
        #expect(keychain.items[.init(account: "accounts", group: appGroup)] == Data("old".utf8))
    }

    @Test func `an old copy that can't be deleted still counts as moved`() {
        let keychain = FakeKeychain(groups: [sharedGroup, appGroup], failsDeletes: true)
        keychain.put(Data("accounts".utf8), account: "accounts", group: appGroup)

        #expect(KeychainStore.moveItems(service: service, into: sharedGroup, keychain: keychain) == .moved(1))
        #expect(keychain.items[.init(account: "accounts", group: sharedGroup)] == Data("accounts".utf8))
    }

    @Test func `the shared group comes from Info.plist only when the team prefix was filled in`() {
        #expect(SharedStorage.accessGroup(fromInfoValue: "2Q2L4AY8HC.com.revanthv11.anemone.shared")
            == "2Q2L4AY8HC.com.revanthv11.anemone.shared")
        #expect(SharedStorage.accessGroup(fromInfoValue: ".com.revanthv11.anemone.shared") == nil)
        #expect(SharedStorage.accessGroup(fromInfoValue: "$(AppIdentifierPrefix)com.revanthv11.anemone.shared") == nil)
        #expect(SharedStorage.accessGroup(fromInfoValue: "") == nil)
        #expect(SharedStorage.accessGroup(fromInfoValue: nil) == nil)
    }

    @Test func `the sign-ins survive the move through the repository`() throws {
        let keychain = FakeKeychain(groups: [sharedGroup, appGroup])
        var accounts = AccountStore(deviceID: "device")
        try accounts.save(SavedServer(
            id: "srv",
            name: "Home",
            url: #require(URL(string: "http://nas.local:8096")),
            version: "12.3.0",
        ))
        try AccountRepository(store: KeychainStore(service: service, keychain: keychain)).save(accounts)

        KeychainStore.moveItems(service: service, into: sharedGroup, keychain: keychain)

        let shared = AccountRepository(store: KeychainStore(
            service: service,
            accessGroup: sharedGroup,
            keychain: keychain,
        ))
        #expect(try shared.load() == accounts)
        #expect(shared.loadReadOnly() == accounts)
    }

    @Test func `reading for the Top Shelf never sets an unreadable item aside`() {
        let keychain = FakeKeychain(groups: [sharedGroup])
        keychain.put(Data("not json".utf8), account: "accounts", group: sharedGroup)
        let repository = AccountRepository(store: KeychainStore(
            service: service,
            accessGroup: sharedGroup,
            keychain: keychain,
        ))

        #expect(repository.loadReadOnly() == nil)
        #expect(keychain.items.count == 1)
        #expect(AccountRepository(store: KeychainStore(service: service, keychain: FakeKeychain(groups: [appGroup])))
            .loadReadOnly() == nil)
    }
}

/// A Keychain with access groups. Like the real one, the first group is where items go when
/// none is given, reads without a group search them all, and a group the app isn't entitled to
/// fails with `errSecMissingEntitlement`.
private final class FakeKeychain: KeychainItems {
    struct Key: Hashable {
        var account: String
        var group: String
        var service = "com.revanthv11.anemone"
    }

    private let groups: [String]
    private let failsDeletes: Bool
    private let storage = Mutex<[Key: Data]>([:])

    init(groups: [String], failsDeletes: Bool = false) {
        self.groups = groups
        self.failsDeletes = failsDeletes
    }

    var items: [Key: Data] {
        storage.withLock { $0 }
    }

    func put(_ data: Data, account: String, group: String, service: String = "com.revanthv11.anemone") {
        storage.withLock { $0[Key(account: account, group: group, service: service)] = data }
    }

    func entries(service: String) throws -> [KeychainEntry] {
        storage.withLock { items in
            items.keys
                .filter { $0.service == service }
                .sorted { ($0.group, $0.account) < ($1.group, $1.account) }
                .map { KeychainEntry(account: $0.account, accessGroup: $0.group) }
        }
    }

    func data(service: String, account: String, accessGroup: String?) throws -> Data? {
        let searched = try searchedGroups(accessGroup)
        return storage.withLock { items in
            searched.compactMap { items[Key(account: account, group: $0, service: service)] }.first
        }
    }

    func save(_ data: Data, service: String, account: String, accessGroup: String?) throws {
        let group = try accessGroup.map { try entitled($0) } ?? groups[0]
        storage.withLock { $0[Key(account: account, group: group, service: service)] = data }
    }

    func delete(service: String, account: String, accessGroup: String?) throws {
        let searched = try searchedGroups(accessGroup)
        if failsDeletes {
            throw KeychainStore.Failure(status: errSecInteractionNotAllowed)
        }
        storage.withLock { items in
            for group in searched {
                items[Key(account: account, group: group, service: service)] = nil
            }
        }
    }

    private func searchedGroups(_ group: String?) throws -> [String] {
        try group.map { try [entitled($0)] } ?? groups
    }

    private func entitled(_ group: String) throws -> String {
        guard groups.contains(group) else { throw KeychainStore.Failure(status: errSecMissingEntitlement) }
        return group
    }
}
