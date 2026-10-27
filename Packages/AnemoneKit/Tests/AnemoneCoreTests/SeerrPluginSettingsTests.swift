#if ANEMONE_SEERR
    import AnemoneCore
    import Foundation
    import Testing

    /// Reading the companion plugin's Seerr settings, as its `SeerrConfig` is written.
    struct SeerrPluginSettingsTests {
        private func decode(_ json: String) throws -> SeerrPluginSettings {
            try JSONDecoder().decode(SeerrPluginSettings.self, from: Data(json.utf8))
        }

        @Test func `an API key login`() throws {
            let settings = try decode(#"""
            {"version":1,"serverUrl":"https://seerr.example.com","login":{"type":"ApiKey","apiKey":"k","local":null}}
            """#)

            #expect(settings.address == "https://seerr.example.com")
            #expect(settings.login == .apiKey("k"))
            #expect(settings.canSignIn)
        }

        @Test func `a shared local account`() throws {
            let settings = try decode(#"""
            {"serverUrl":"https://seerr.example.com",
             "login":{"type":"Local","apiKey":null,"local":{"username":"house@example.com","password":"pw"}}}
            """#)

            #expect(settings.version == 1)
            #expect(settings.login == .local(username: "house@example.com", password: "pw"))
        }

        @Test func `only the address, for the user to sign in themselves`() throws {
            let withoutLogin = try decode(#"{"version":1,"serverUrl":"https://seerr.example.com"}"#)
            let nullLogin = try decode(#"{"version":1,"serverUrl":"https://seerr.example.com","login":null}"#)
            let noneLogin = try decode(#"{"serverUrl":"https://seerr.example.com","login":{"type":"None"}}"#)

            for settings in [withoutLogin, nullLogin, noneLogin] {
                #expect(settings.login == .none)
                #expect(settings.address == "https://seerr.example.com")
                #expect(!settings.canSignIn)
            }
        }

        @Test func `an unknown or incomplete login keeps the address`() throws {
            let unknown =
                try decode(#"{"serverUrl":"https://s.example","login":{"type":"Jellyfin","useCurrentUser":true}}"#)
            let noKey = try decode(#"{"serverUrl":"https://s.example","login":{"type":"ApiKey","apiKey":""}}"#)
            let noPassword =
                try decode(#"{"serverUrl":"https://s.example","login":{"type":"Local","local":{"username":"a"}}}"#)
            let notAnObject = try decode(#"{"serverUrl":"https://s.example","login":"ApiKey"}"#)

            for settings in [unknown, noKey, noPassword, notAnObject] {
                #expect(settings.login == .none)
                #expect(settings.address == "https://s.example")
            }
        }

        @Test func `a blank address can't be signed in to`() throws {
            let settings = try decode(#"{"serverUrl":"  ","login":{"type":"ApiKey","apiKey":"k"}}"#)

            #expect(settings.address == nil)
            #expect(!settings.canSignIn)
        }

        @Test func `descriptions never show the credentials`() {
            let key = SeerrPluginSettings(serverURL: "https://s.example", login: .apiKey("secret-key"))
            let local = SeerrPluginSettings(
                serverURL: "https://s.example",
                login: .local(username: "u", password: "pw1"),
            )

            for text in ["\(key)", String(reflecting: key), "\(key.login)"] {
                #expect(!text.contains("secret-key"))
            }
            for text in ["\(local)", String(reflecting: local), "\(local.login)"] {
                #expect(!text.contains("pw1"))
            }
        }
    }
#endif
