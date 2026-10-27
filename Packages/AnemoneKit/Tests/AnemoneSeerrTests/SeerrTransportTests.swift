#if ANEMONE_SEERR
    @testable import AnemoneSeerr
    import Foundation
    import Testing

    struct SeerrTransportTests {
        @Test func `checking addresses leaves no session open`() async throws {
            let host = "probes.transport.seerr.test"
            SeerrMockServer.register(host: host) { _ in nil }

            await #expect(throws: SeerrError.unexpectedResponse) {
                try await SeerrConnection.signIn(
                    atAddress: host,
                    with: .apiKey("key"),
                    configuration: { SeerrMockServer.configuration() },
                )
            }

            // Every guessed address was checked, each with a session of its own.
            #expect(SeerrMockServer.requests(to: host).count == 4)
            #expect(SeerrTransport.openSessions(to: host) == 0)
        }

        @Test func `a connection keeps one session, closed once the connection has gone`() async throws {
            let host = "connection.transport.seerr.test"
            SeerrMockServer.register(host: host, handler: SeerrJSON.server())

            var seerr: SeerrConnection? = try await SeerrConnection.signIn(
                atAddress: host,
                with: .local(username: "alice", password: "secret"),
                configuration: { SeerrMockServer.configuration() },
            )

            // The address check's session has closed; the connection's is open.
            withExtendedLifetime(seerr) {
                #expect(seerr?.user.name == "alice")
                #expect(SeerrTransport.openSessions(to: host) == 1)
            }
            seerr = nil
            #expect(SeerrTransport.openSessions(to: host) == 0)
        }
    }
#endif
