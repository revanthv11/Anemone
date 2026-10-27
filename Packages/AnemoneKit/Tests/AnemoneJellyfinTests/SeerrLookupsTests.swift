#if ANEMONE_SEERR
    import AnemoneCore
    @testable import AnemoneJellyfin
    import Foundation
    import Testing

    /// What Seerr needs from Jellyfin: the companion plugin's Seerr settings (Wholphin's
    /// `fetchSeerrSettings` at `cecfdae`) and items' TMDB IDs.
    struct SeerrLookupsTests {
        @Test func `reads the plugin's Seerr server and login`() async throws {
            // As the plugin's .NET serializer writes it: every property, nulls included.
            let server = HomeServer("seerr-plugin.test") { path, _ in
                guard path == "/wholphin/seerrsettings" else { return nil }
                return .json(#"""
                {"version":1,"serverUrl":"https://seerr.example.com",
                 "login":{"type":"ApiKey","apiKey":"shared-key","local":null}}
                """#)
            }

            let settings = try await server.session().serverPluginSeerrSettings()

            #expect(settings == SeerrPluginSettings(
                serverURL: "https://seerr.example.com",
                login: .apiKey("shared-key"),
            ))
            let sent = try #require(server.requests(to: "/wholphin/seerrsettings").first)
            #expect(sent.method == "GET")
        }

        @Test func `a server without the plugin, or with no Seerr server set, has none`() async throws {
            let server = HomeServer("seerr-noplugin.test") { _, _ in .notFound }

            #expect(try await server.session().serverPluginSeerrSettings() == nil)
        }

        @Test func `a revoked token is a sign-out`() async throws {
            let server = HomeServer("seerr-signedout.test") { _, _ in .unauthorized }

            await #expect(throws: SessionError.signedOut) {
                try await server.session().serverPluginSeerrSettings()
            }
        }

        @Test func `an item's TMDB ID comes from its provider IDs`() async throws {
            let server = HomeServer("seerr-tmdb.test") { path, _ in
                switch path {
                case "/Users/u1/Items/m1", "/Items/m1":
                    .json(#"{"Id":"m1","Name":"Film","Type":"Movie","ProviderIds":{"Imdb":"tt0133093","Tmdb":"603"}}"#)
                case "/Users/u1/Items/m2", "/Items/m2":
                    .json(#"{"Id":"m2","Name":"Home video","Type":"Video","ProviderIds":{}}"#)
                default:
                    nil
                }
            }

            #expect(try await server.session().tmdbID(ofItem: "m1") == 603)
            #expect(try await server.session().tmdbID(ofItem: "m2") == nil)
        }
    }
#endif
