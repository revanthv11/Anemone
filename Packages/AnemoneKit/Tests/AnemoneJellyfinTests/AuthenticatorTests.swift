import AnemoneJellyfin
import Foundation
import Synchronization
import Testing

struct AuthenticatorTests {
    private let authenticator = Authenticator(
        identity: ClientIdentity(deviceName: "Test TV", deviceID: "device-1", appVersion: "0.1.0"),
        sessionConfiguration: { MockServer.sessionConfiguration() },
    )

    @Test func `signs in with a password and identifies as Anemone`() async throws {
        let authorization = Mutex<String?>(nil)
        MockServer.register(host: "password.test") { request in
            guard request.url?.path() == "/Users/AuthenticateByName" else { return nil }
            authorization.withLock { $0 = request.value(forHTTPHeaderField: "Authorization") }
            return .authentication()
        }

        let user = try await authenticator.signIn(
            to: #require(URL(string: "https://password.test")),
            username: "alice",
            password: "secret",
        )

        #expect(user == SignedInUser(id: "u1", name: "Alice", primaryImageTag: nil, accessToken: "tok"))
        let header = try #require(authorization.withLock { $0 })
        #expect(header.hasPrefix("MediaBrowser "))
        #expect(header.contains("Client=Anemone"))
        #expect(header.contains("DeviceId=device-1"))
    }

    @Test func `reports a rejected password`() async throws {
        MockServer.register(host: "wrong.test") { _ in .unauthorized }

        await #expect(throws: AuthenticationError.invalidCredentials) {
            try await authenticator.signIn(
                to: #require(URL(string: "https://wrong.test")),
                username: "a",
                password: "b",
            )
        }
    }

    @Test func `lists public users`() async throws {
        MockServer.register(host: "users.test") { _ in
            .json(#"""
            [{"Id":"u1","Name":"Alice","HasConfiguredPassword":true},
             {"Id":"u2","Name":"Kids","HasConfiguredPassword":false}]
            """#)
        }

        let users = try await authenticator.publicUsers(on: #require(URL(string: "https://users.test")))

        #expect(users.map(\.name) == ["Alice", "Kids"])
    }

    @Test func `treats a rejected token as signed out`() async throws {
        MockServer.register(host: "expired.test") { _ in .unauthorized }

        let user = try await authenticator.currentUser(
            on: #require(URL(string: "https://expired.test")),
            token: "old",
        )

        #expect(user == nil)
    }

    @Test func `quick connect shows the code, then signs in once approved`() async throws {
        let polls = Mutex(0)
        MockServer.register(host: "quick.test") { request in
            switch request.url?.path() {
            case "/QuickConnect/Initiate":
                return .json(#"{"Authenticated":false,"Secret":"s1","Code":"123456"}"#)
            case "/QuickConnect/Connect":
                let approved = polls.withLock { count in
                    count += 1
                    return count > 1
                }
                return .json(#"{"Authenticated":\#(approved),"Secret":"s1","Code":"123456"}"#)
            case "/Users/AuthenticateWithQuickConnect":
                return .authentication(token: "qc-token", userID: "u2", name: "Bob")
            default:
                return nil
            }
        }

        var progress: [QuickConnectProgress] = []
        for try await step in try authenticator.quickConnect(
            to: #require(URL(string: "https://quick.test")),
            pollInterval: 1,
        ) {
            progress.append(step)
        }

        #expect(progress == [
            .code("123456"),
            .signedIn(SignedInUser(id: "u2", name: "Bob", primaryImageTag: nil, accessToken: "qc-token")),
        ])
    }
}
