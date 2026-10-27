#if ANEMONE_SEERR
    import AnemoneCore
    @testable import AnemoneSeerr
    import Foundation
    import Synchronization
    import Testing

    /// Keeping a connection signed in once Seerr's session lapses, as when the server restarts.
    struct SeerrSessionTests {
        private func serverURL(_ host: String) throws -> URL {
            try #require(URL(string: "https://\(host)/"))
        }

        private func signIn(_ seerr: LapsingSeerr) async throws -> SeerrConnection {
            try await SeerrConnection.signIn(
                to: serverURL(seerr.host),
                with: .local(username: "alice", password: "hunter2"),
                configuration: SeerrMockServer.configuration(),
            )
        }

        /// What was sent after signing in, which takes three requests.
        private func sentSinceSignIn(to host: String) -> [String] {
            SeerrMockServer.requests(to: host).dropFirst(3).map(\.path)
        }

        @Test func `a lapsed session signs in again once and sends the request again`() async throws {
            let seerr = LapsingSeerr(host: "lapse.session.seerr.test")
            let connection = try await signIn(seerr)
            seerr.lapse()

            let items = try await connection.discover(.popularMovies)

            #expect(items.isEmpty)
            #expect(sentSinceSignIn(to: seerr.host) == [
                "/api/v1/discover/movies",
                "/api/v1/auth/me",
                "/api/v1/auth/local",
                "/api/v1/discover/movies",
            ])
            let resent = try #require(SeerrMockServer.requests(to: seerr.host).last)
            #expect(resent.header("Cookie") == "connect.sid=s2")
        }

        @Test func `requests turned down together sign in again once`() async throws {
            let seerr = LapsingSeerr(host: "together.session.seerr.test")
            let connection = try await signIn(seerr)
            seerr.lapse()

            async let first = connection.discover(.popularMovies)
            async let second = connection.discover(.popularMovies)
            async let third = connection.discover(.popularMovies)
            _ = try await (first, second, third)

            #expect(seerr.signIns == 2)
        }

        @Test func `a request turned down while the session still works isn't sent again`() async throws {
            let seerr = LapsingSeerr(host: "forbidden.session.seerr.test")
            let connection = try await signIn(seerr)

            await #expect(throws: (any Error).self) {
                try await connection.discover(.popularSeries)
            }

            #expect(sentSinceSignIn(to: seerr.host) == ["/api/v1/discover/tv", "/api/v1/auth/me"])
            #expect(seerr.signIns == 1)
        }

        @Test func `when signing in again fails, the connection is signed out for good`() async throws {
            let seerr = LapsingSeerr(host: "refused.session.seerr.test")
            let connection = try await signIn(seerr)
            let signedOut = Counter()
            connection.onSignedOut { signedOut.add() }
            seerr.lapse()
            seerr.changePassword(to: "changed")

            await #expect(throws: (any Error).self) {
                try await connection.discover(.popularMovies)
            }
            #expect(signedOut.value == 1)
            await #expect(throws: (any Error).self) {
                try await connection.discover(.popularMovies)
            }

            // The second request isn't followed by another sign-in.
            let sent = sentSinceSignIn(to: seerr.host)
            #expect(sent == [
                "/api/v1/discover/movies",
                "/api/v1/auth/me",
                "/api/v1/auth/local",
                "/api/v1/discover/movies",
            ])
            #expect(signedOut.value == 1)
            // Told right away once it has happened.
            connection.onSignedOut { signedOut.add() }
            #expect(signedOut.value == 2)
        }

        @Test func `an API key Seerr no longer takes signs the connection out`() async throws {
            let seerr = LapsingSeerr(host: "revoked.session.seerr.test")
            let connection = try await SeerrConnection.signIn(
                to: serverURL(seerr.host),
                with: .apiKey("key"),
                configuration: SeerrMockServer.configuration(),
            )
            let signedOut = Counter()
            connection.onSignedOut { signedOut.add() }
            seerr.revokeKey()

            await #expect(throws: (any Error).self) {
                try await connection.discover(.popularMovies)
            }

            // An API key has nothing to sign in with: it's checked, then given up on.
            let sent = SeerrMockServer.requests(to: seerr.host).dropFirst(2).map(\.path)
            #expect(sent == ["/api/v1/discover/movies", "/api/v1/auth/me"])
            #expect(signedOut.value == 1)
        }

        @Test func `the profile's own account signs in again with the Keychain's password`() async throws {
            let seerr = LapsingSeerr(host: "keychain.session.seerr.test")
            let store = InMemorySecureStore()
            let accounts = SeerrAccountStore(store: store)
            let profile = SeerrAccountStore.Profile(serverID: "srv1", userID: "u1")
            let account = try SeerrAccount(
                serverURL: serverURL(seerr.host),
                method: .local,
                username: "alice",
                secret: "hunter2",
            )
            try accounts.save(account, for: profile)
            let signIn = SeerrSignIn(accounts: accounts, profile: profile) { SeerrMockServer.configuration() }
            let connection = try #require(await signIn.connect { nil }.connection)
            // The password changes in Seerr and in Settings › Seerr while signed in.
            seerr.changePassword(to: "changed")
            try accounts.save(
                SeerrAccount(serverURL: account.serverURL, method: .local, username: "alice", secret: "changed"),
                for: profile,
            )
            seerr.lapse()

            _ = try await connection.discover(.popularMovies)

            let signIns = SeerrMockServer.requests(to: seerr.host).filter { $0.path == "/api/v1/auth/local" }
            #expect(signIns.map { $0.json["password"] as? String } == ["hunter2", "changed"])
            #expect(seerr.signIns == 2)
        }

        @Test func `signing in leaves the caller's configuration as it was`() async throws {
            let seerr = LapsingSeerr(host: "configuration.session.seerr.test")
            let configuration = SeerrMockServer.configuration()
            configuration.timeoutIntervalForRequest = 45

            #expect(try await SeerrConnection.isSeerr(at: serverURL(seerr.host), configuration))
            _ = try await SeerrConnection.signIn(
                to: serverURL(seerr.host),
                with: .apiKey("key"),
                configuration: configuration,
            )

            #expect(configuration.timeoutIntervalForRequest == 45)
            #expect(configuration.httpShouldSetCookies)
            #expect(configuration.httpCookieAcceptPolicy != .never)
            #expect(configuration.httpCookieStorage != nil)
        }
    }

    /// A fake Seerr whose session can lapse. Each password sign-in gets a cookie of its own, and
    /// only the latest is taken, until `lapse()` forgets it; the API key "key" works until
    /// `revokeKey()`. Series are off limits to everyone, to turn a signed-in request down.
    private final class LapsingSeerr: Sendable {
        let host: String
        private let state = Mutex(State())

        private struct State {
            var password = "hunter2"
            var cookie: String?
            var signIns = 0
            var keyWorks = true
        }

        init(host: String) {
            self.host = host
            SeerrMockServer.register(host: host) { [self] request in
                reply(to: request)
            }
        }

        var signIns: Int {
            state.withLock(\.signIns)
        }

        func lapse() {
            state.withLock { $0.cookie = nil }
        }

        func changePassword(to password: String) {
            state.withLock { $0.password = password }
        }

        func revokeKey() {
            state.withLock { $0.keyWorks = false }
        }

        private func reply(to request: Sent) -> SeerrMockServer.Reply? {
            switch (request.method, request.path) {
            case ("GET", "/api/v1/settings/public"):
                return .json(SeerrJSON.publicSettings)
            case ("POST", "/api/v1/auth/local"):
                let password = request.json["password"] as? String
                return state.withLock { state -> SeerrMockServer.Reply in
                    state.signIns += 1
                    guard password == state.password else { return .status(401) }
                    state.cookie = "connect.sid=s\(state.signIns)"
                    return .json(SeerrJSON.user(), headers: ["Set-Cookie": "connect.sid=s\(state.signIns); Path=/"])
                }
            default:
                let isSignedIn = state.withLock { state in
                    (state.cookie != nil && request.header("Cookie") == state.cookie)
                        || (state.keyWorks && request.header("X-Api-Key") == "key")
                }
                guard isSignedIn else { return .status(403) }
                switch request.path {
                case "/api/v1/auth/me":
                    return .json(SeerrJSON.user())
                case "/api/v1/discover/movies":
                    return .json(#"{"page":1,"totalPages":1,"totalResults":0,"results":[]}"#)
                default:
                    return .status(403)
                }
            }
        }
    }

    private final class Counter: Sendable {
        private let count = Mutex(0)

        var value: Int {
            count.withLock(\.self)
        }

        func add() {
            count.withLock { $0 += 1 }
        }
    }
#endif
