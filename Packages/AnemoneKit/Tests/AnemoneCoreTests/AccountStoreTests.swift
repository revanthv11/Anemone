import AnemoneCore
import Foundation
import Testing

struct AccountStoreTests {
    private let home = SavedServer(
        id: "srv-home",
        name: "Home",
        url: URL(string: "http://nas.local:8096")!,
        version: "12.3.0",
        lastUsed: Date(timeIntervalSince1970: 100),
    )
    private let cabin = SavedServer(
        id: "srv-cabin",
        name: "Cabin",
        url: URL(string: "https://cabin.example.com")!,
        version: "12.1.0",
        lastUsed: Date(timeIntervalSince1970: 200),
    )

    @Test func `saving a server with a known ID replaces it`() throws {
        var store = AccountStore(deviceID: "device")
        store.save(home)
        var moved = home
        moved.url = try #require(URL(string: "http://10.0.0.2:8096"))
        store.save(moved)

        #expect(store.servers == [moved])
    }

    @Test func `lists servers and users by most recent use`() {
        var store = AccountStore(deviceID: "device")
        store.save(home)
        store.save(cabin)
        store.save(user("alice", on: home, lastUsed: 1))
        store.save(user("bob", on: home, lastUsed: 2))
        store.save(user("carol", on: cabin, lastUsed: 3))

        #expect(store.serversByRecentUse.map(\.id) == ["srv-cabin", "srv-home"])
        #expect(store.users(on: home.id).map(\.id) == ["bob", "alice"])
    }

    @Test func `removing a server removes its users and last session`() {
        var store = AccountStore(deviceID: "device")
        store.save(home)
        store.save(cabin)
        store.save(user("alice", on: home))
        store.save(user("carol", on: cabin))
        store.lastSession = .init(serverID: home.id, userID: "alice")

        store.removeServer(id: home.id)

        #expect(store.servers == [cabin])
        #expect(store.users.map(\.id) == ["carol"])
        #expect(store.lastSession == nil)
    }

    @Test func `signing out keeps the profile but drops the token`() {
        var store = AccountStore(deviceID: "device")
        store.save(home)
        store.save(user("alice", on: home))
        store.lastSession = .init(serverID: home.id, userID: "alice")

        store.signOut(userID: "alice", on: home.id)

        #expect(store.user(id: "alice", on: home.id)?.accessToken == nil)
        #expect(store.lastSession == nil)
    }

    @Test func `round-trips through a secure store`() throws {
        let repository = AccountRepository(store: InMemorySecureStore())
        let fresh = try repository.load()
        #expect(fresh.servers.isEmpty)

        var store = fresh
        store.save(home)
        store.save(user("alice", on: home, lock: .pin(PINHash(pin: "1234"))))
        store.lastSession = .init(serverID: home.id, userID: "alice")
        try repository.save(store)

        let loaded = try repository.load()
        #expect(loaded == store)
        #expect(loaded.deviceID == fresh.deviceID)
    }

    @Test func `sets aside saved data it can't decode instead of losing it`() throws {
        let secureStore = InMemorySecureStore()
        let unreadable = Data(#"{"deviceID":"device-7","servers":"from a future format"}"#.utf8)
        try secureStore.set(unreadable, for: "accounts")
        let repository = AccountRepository(store: secureStore)

        let loaded = try repository.load()
        try repository.save(loaded)

        #expect(loaded.servers.isEmpty)
        #expect(loaded.deviceID == "device-7")
        #expect(try secureStore.data(for: "accounts.unreadable") == unreadable)
    }

    private func user(
        _ id: String,
        on server: SavedServer,
        lastUsed: TimeInterval = 0,
        lock: ProfileLock = .unlocked,
    ) -> SavedUser {
        SavedUser(
            id: id,
            serverID: server.id,
            name: id.capitalized,
            accessToken: "token-\(id)",
            lock: lock,
            lastUsed: Date(timeIntervalSince1970: lastUsed),
        )
    }
}

struct PINHashTests {
    @Test func `matches only the original PIN`() {
        let hash = PINHash(pin: "2468")
        #expect(hash.matches("2468"))
        #expect(!hash.matches("2469"))
        #expect(!hash.matches(""))
    }

    @Test func `salts each hash`() {
        #expect(PINHash(pin: "1111") != PINHash(pin: "1111"))
    }

    @Test(arguments: [
        ("1234", true),
        ("0000", true),
        ("123", false),
        ("12345", false),
        ("12a4", false),
        ("١٢٣٤", false)
    ])
    func `validates new PINs`(pin: String, valid: Bool) {
        #expect(PINHash.isValid(pin) == valid)
    }
}
