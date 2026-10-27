#if ANEMONE_SEERR
    @testable import AnemoneSeerr
    import Foundation
    import Testing

    struct SeerrConnectionTests {
        private func serverURL(_ host: String) throws -> URL {
            try #require(URL(string: "https://\(host)"))
        }

        @Test func `signing in with a password sends it once, then the session cookie`() async throws {
            let host = "local.seerr.test"
            SeerrMockServer.register(host: host, handler: SeerrJSON.server(permissions: 262_176))

            let connection = try await SeerrConnection.signIn(
                to: serverURL(host),
                with: .local(username: "alice@example.com", password: "hunter2"),
                configuration: SeerrMockServer.configuration(),
            )

            let sent = SeerrMockServer.requests(to: host)
            #expect(sent.map(\.path) == ["/api/v1/auth/local", "/api/v1/auth/me", "/api/v1/settings/public"])
            #expect(sent[0].method == "POST")
            #expect(sent[0].json["email"] as? String == "alice@example.com")
            #expect(sent[0].json["password"] as? String == "hunter2")
            #expect(sent[0].header("Cookie") == nil)
            #expect(sent[1].header("Cookie") == "connect.sid=s%3Asecret")
            #expect(sent[1].header("X-Api-Key") == nil)
            #expect(connection.user == SeerrUser(
                id: 7,
                name: "alice",
                permissions: SeerrPermissions(rawValue: 262_176),
            ))
            #expect(connection.canRequestMovies)
        }

        @Test func `signing in with Jellyfin sends the username`() async throws {
            let host = "jellyfin.seerr.test"
            SeerrMockServer.register(host: host, handler: SeerrJSON.server())

            _ = try await SeerrConnection.signIn(
                to: serverURL(host),
                with: .jellyfin(username: "alice", password: "hunter2"),
                configuration: SeerrMockServer.configuration(),
            )

            let login = try #require(SeerrMockServer.requests(to: host).first)
            #expect(login.path == "/api/v1/auth/jellyfin")
            #expect(login.json["username"] as? String == "alice")
        }

        @Test func `an API key goes with every request and nothing signs in`() async throws {
            let host = "key.seerr.test"
            SeerrMockServer.register(host: host, handler: SeerrJSON.server())

            _ = try await SeerrConnection.signIn(
                to: serverURL(host),
                with: .apiKey("abc123"),
                configuration: SeerrMockServer.configuration(),
            )

            let sent = SeerrMockServer.requests(to: host)
            #expect(sent.map(\.path) == ["/api/v1/auth/me", "/api/v1/settings/public"])
            #expect(sent.allSatisfy { $0.header("X-Api-Key") == "abc123" })
        }

        @Test func `a wrong password is reported as such`() async throws {
            let host = "denied.seerr.test"
            SeerrMockServer.register(host: host) { request in
                request.path == "/api/v1/auth/local" ? .status(403) : .json("{}")
            }

            await #expect(throws: SeerrError.invalidCredentials) {
                try await SeerrConnection.signIn(
                    to: serverURL(host),
                    with: .local(username: "alice", password: "wrong"),
                    configuration: SeerrMockServer.configuration(),
                )
            }
        }

        @Test func `a typed address is checked before the password is sent to it`() async throws {
            // Only Seerr's own port answers, so the default port's address is skipped.
            let host = "typed.seerr.test"
            SeerrMockServer.register(host: host) { request in
                request.url?.port == 5055 ? SeerrJSON.server()(request) : nil
            }

            let connection = try await SeerrConnection.signIn(
                atAddress: host,
                with: .local(username: "alice", password: "hunter2"),
                configuration: { SeerrMockServer.configuration() },
            )

            #expect(connection.serverURL.absoluteString == "https://typed.seerr.test:5055/")
            let sent = SeerrMockServer.requests(to: host)
            let withPassword = sent.filter { $0.path == "/api/v1/auth/local" }
            #expect(withPassword.count == 1)
            #expect(withPassword.first?.url?.absoluteString == "https://typed.seerr.test:5055/api/v1/auth/local")
            #expect(sent.first?.url?.absoluteString == "https://typed.seerr.test/api/v1/settings/public")
        }

        @Test func `no Seerr at any guessed address means no sign-in at all`() async throws {
            let host = "nobody.seerr.test"
            SeerrMockServer.register(host: host) { _ in nil }

            await #expect(throws: SeerrError.unexpectedResponse) {
                try await SeerrConnection.signIn(
                    atAddress: host,
                    with: .apiKey("abc"),
                    configuration: { SeerrMockServer.configuration() },
                )
            }
            #expect(SeerrMockServer.requests(to: host).allSatisfy { $0.path == "/api/v1/settings/public" })
        }

        @Test func `4K is offered only when the server allows it and the user may`() async throws {
            let host = "fourk.seerr.test"
            SeerrMockServer.register(host: host, handler: SeerrJSON.server(
                permissions: 32 | 2048,
                settings: #"{"movie4kEnabled":true,"series4kEnabled":false,"cacheImages":true}"#,
            ))

            let connection = try await SeerrConnection.signIn(
                to: serverURL(host),
                with: .apiKey("abc"),
                configuration: SeerrMockServer.configuration(),
            )

            #expect(connection.canRequest4KMovies)
            #expect(!connection.canRequest4KSeries)
            #expect(connection.settings.cachesImages)
        }
    }
#endif
