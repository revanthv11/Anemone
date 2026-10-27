import AnemoneJellyfin
import Foundation

/// A session on a fake server for the library tests.
func librarySession(host: String) throws -> JellyfinSession {
    guard let url = URL(string: "https://\(host)") else { throw URLError(.badURL) }
    return JellyfinSession(
        serverURL: url,
        userID: "u1",
        accessToken: "tok",
        identity: ClientIdentity(deviceName: "Test TV", deviceID: "device-1", appVersion: "0.1.0"),
        sessionConfiguration: { MockServer.sessionConfiguration() },
    )
}
