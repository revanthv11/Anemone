import AnemoneJellyfin
import Foundation
import Testing

struct ClientIdentityTests {
    @Test func `configures client`() throws {
        let identity = ClientIdentity(deviceName: "Living Room", deviceID: "device-1", appVersion: "0.1.0")
        let url = try #require(URL(string: "http://jellyfin.local:8096"))

        let configuration = identity.makeClient(serverURL: url, accessToken: "token").configuration

        #expect(configuration.url == url)
        #expect(configuration.accessToken == "token")
        #expect(configuration.client == "Anemone")
        #expect(configuration.deviceName == "Living Room")
        #expect(configuration.deviceID == "device-1")
        #expect(configuration.version == "0.1.0")
    }
}
