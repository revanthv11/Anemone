import AnemoneJellyfin
import Foundation
import Testing

struct ServerConnectorTests {
    private let connector = ServerConnector(
        identity: ClientIdentity(deviceName: "Test TV", deviceID: "device-1", appVersion: "0.1.0"),
        sessionConfiguration: { MockServer.sessionConfiguration() },
    )

    @Test func `falls back to Jellyfin's default HTTP port`() async throws {
        MockServer.register(host: "fallback.test") { request in
            request.url?.scheme == "http" && request.url?.port == 8096 ? .publicInfo() : nil
        }

        let server = try await connector.connect(to: "fallback.test")

        #expect(try server == ConnectedServer(
            id: "srv1",
            name: "Living Room",
            version: "12.3.0",
            url: #require(URL(string: "http://fallback.test:8096")),
        ))
    }

    @Test func `keeps a reverse-proxy path`() async throws {
        MockServer.register(host: "proxy.test") { request in
            request.url?.path() == "/jellyfin/System/Info/Public" ? .publicInfo() : nil
        }

        let server = try await connector.connect(to: "https://proxy.test/jellyfin")

        #expect(server.url.absoluteString == "https://proxy.test/jellyfin")
    }

    @Test func `rejects servers older than Jellyfin 12`() async {
        MockServer.register(host: "old.test") { _ in .publicInfo(version: "10.11.2") }

        await #expect(throws: ServerConnectionError.unsupportedVersion("10.11.2")) {
            try await connector.connect(to: "https://old.test")
        }
    }

    @Test func `rejects servers that haven't finished setup`() async {
        MockServer.register(host: "new.test") { _ in .publicInfo(wizardDone: false) }

        await #expect(throws: ServerConnectionError.setupIncomplete) {
            try await connector.connect(to: "https://new.test")
        }
    }

    @Test func `reports unreachable servers`() async {
        MockServer.register(host: "down.test") { _ in nil }

        await #expect(throws: ServerConnectionError.unreachable) {
            try await connector.connect(to: "down.test")
        }
    }

    @Test func `rejects text that isn't an address`() async {
        await #expect(throws: ServerConnectionError.invalidAddress) {
            try await connector.connect(to: "not an address")
        }
    }
}
