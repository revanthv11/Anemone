#if ANEMONE_SEERR
    import AnemoneCore
    @testable import AnemoneSeerr
    import Foundation
    import Testing

    /// The plugin-first sign-in ported from Wholphin's `UserSwitchListener` at `cecfdae`, with its
    /// three quirks fixed.
    struct SeerrSignInTests {
        private struct PluginDown: Error {}

        private let profile = SeerrAccountStore.Profile(serverID: "srv1", userID: "u1")

        private func signIn(_ store: InMemorySecureStore) -> SeerrSignIn {
            SeerrSignIn(
                accounts: SeerrAccountStore(store: store),
                profile: profile,
                configuration: { SeerrMockServer.configuration() },
            )
        }

        private func saveAccount(in store: InMemorySecureStore, host: String) throws {
            try SeerrAccountStore(store: store).save(
                SeerrAccount(
                    serverURL: #require(URL(string: "https://\(host)/")),
                    method: .local,
                    username: "alice",
                    secret: "hunter2",
                ),
                for: profile,
            )
        }

        @Test func `the plugin's API key signs in and nothing is saved`() async throws {
            let host = "plugin-key.seerr.test"
            SeerrMockServer.register(host: host, handler: SeerrJSON.server())
            let store = InMemorySecureStore()

            let status = await signIn(store).connect {
                SeerrPluginSettings(serverURL: "https://\(host)", login: .apiKey("shared-key"))
            }

            guard case let .connected(connection, isManagedByServer) = status else {
                Issue.record("Expected a connection, got \(status)")
                return
            }
            #expect(isManagedByServer)
            #expect(connection.serverURL.host() == host)
            #expect(SeerrMockServer.requests(to: host).last?.header("X-Api-Key") == "shared-key")
            #expect(try store.data(for: "seerr.srv1.u1") == nil)
        }

        @Test func `the plugin's shared account signs in with its password`() async throws {
            let host = "plugin-local.seerr.test"
            SeerrMockServer.register(host: host, handler: SeerrJSON.server())
            let store = InMemorySecureStore()
            try saveAccount(in: store, host: "unused.seerr.test")

            let status = await signIn(store).connect {
                SeerrPluginSettings(serverURL: host, login: .local(username: "house@example.com", password: "pw"))
            }

            #expect(status.connection != nil)
            let login = SeerrMockServer.requests(to: host).first { $0.path == "/api/v1/auth/local" }
            #expect(login?.json["email"] as? String == "house@example.com")
            // The plugin wins over the profile's own account.
            #expect(SeerrMockServer.requests(to: "unused.seerr.test").isEmpty)
        }

        @Test func `a plugin that fails falls back to the profile's own account, which can be removed`() async throws {
            SeerrMockServer.register(host: "broken.seerr.test") { request in
                request.path == "/api/v1/settings/public" ? .json("{}") : .status(403)
            }
            let own = "own.seerr.test"
            SeerrMockServer.register(host: own, handler: SeerrJSON.server())
            let store = InMemorySecureStore()
            try saveAccount(in: store, host: own)

            let status = await signIn(store).connect {
                SeerrPluginSettings(serverURL: "https://broken.seerr.test", login: .apiKey("stale"))
            }

            guard case let .connected(connection, isManagedByServer) = status else {
                Issue.record("Expected a connection, got \(status)")
                return
            }
            #expect(!isManagedByServer)
            #expect(connection.serverURL.host() == own)
        }

        @Test func `plugin settings that can't be read fall back to the profile's own account`() async throws {
            let own = "fallback.seerr.test"
            SeerrMockServer.register(host: own, handler: SeerrJSON.server())
            let store = InMemorySecureStore()
            try saveAccount(in: store, host: own)

            let status = await signIn(store).connect { throw PluginDown() }

            #expect(status.connection?.serverURL.host() == own)
        }

        @Test func `a plugin address without a login is offered to the add page`() async {
            let status = await signIn(InMemorySecureStore()).connect {
                SeerrPluginSettings(serverURL: "https://seerr.example.com", login: .none)
            }

            guard case let .notConfigured(suggestedAddress) = status else {
                Issue.record("Expected no connection, got \(status)")
                return
            }
            #expect(suggestedAddress == "https://seerr.example.com")
        }

        @Test func `a failing plugin with no account of the profile's own offers a retry`() async {
            SeerrMockServer.register(host: "down.seerr.test") { _ in nil }

            let status = await signIn(InMemorySecureStore()).connect {
                SeerrPluginSettings(serverURL: "https://down.seerr.test", login: .apiKey("key"))
            }

            guard case let .failed(failure) = status else {
                Issue.record("Expected a failure, got \(status)")
                return
            }
            #expect(failure.isManagedByServer)
            #expect(failure.address == "https://down.seerr.test")
        }

        @Test func `nothing set up anywhere means not configured`() async {
            let status = await signIn(InMemorySecureStore()).connect { nil }

            guard case let .notConfigured(suggestedAddress) = status else {
                Issue.record("Expected no connection, got \(status)")
                return
            }
            #expect(suggestedAddress == nil)
        }

        @Test func `an account the profile's own server turns down is a failure that can be removed`() async throws {
            let host = "expired.seerr.test"
            SeerrMockServer.register(host: host) { request in
                request.path == "/api/v1/auth/local" ? .status(401) : .json("{}")
            }
            let store = InMemorySecureStore()
            try saveAccount(in: store, host: host)

            let status = await signIn(store).connect { nil }

            guard case let .failed(failure) = status else {
                Issue.record("Expected a failure, got \(status)")
                return
            }
            #expect(!failure.isManagedByServer)
            #expect(failure.error as? SeerrError == .invalidCredentials)
        }

        @Test func `adding a server keeps its address and password in the secure store`() async throws {
            let host = "added.seerr.test"
            SeerrMockServer.register(host: host, handler: SeerrJSON.server())
            let store = InMemorySecureStore()

            _ = try await signIn(store).add(
                address: "https://\(host)",
                method: .jellyfin,
                username: "alice",
                secret: "pw",
            )

            let account = try #require(try SeerrAccountStore(store: store).account(for: profile))
            #expect(account.serverURL.absoluteString == "https://\(host)/")
            #expect(account.method == .jellyfin)
            #expect(account.username == "alice")
            #expect(account.secret == "pw")
            #expect(!account.description.contains("pw"))

            try signIn(store).remove()
            #expect(try SeerrAccountStore(store: store).account(for: profile) == nil)
        }

        @Test func `a server that turns the password down isn't saved`() async throws {
            let host = "refuses.seerr.test"
            SeerrMockServer.register(host: host) { request in
                request.path == "/api/v1/auth/jellyfin" ? .status(401) : .json("{}")
            }
            let store = InMemorySecureStore()

            await #expect(throws: SeerrError.invalidCredentials) {
                try await signIn(store).add(address: "https://\(host)", method: .jellyfin, username: "a", secret: "b")
            }
            #expect(try store.data(for: "seerr.srv1.u1") == nil)
        }
    }
#endif
