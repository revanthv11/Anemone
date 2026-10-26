import Foundation
import JellyfinAPI

/// How Anemone identifies itself to Jellyfin servers.
///
/// The server shows these values on its Devices and Activity pages, and uses the device ID to
/// tie access tokens to this Apple TV, so `deviceID` must stay the same across launches.
public struct ClientIdentity: Sendable {
    public static let clientName = "Anemone"

    public let deviceName: String
    public let deviceID: String
    public let appVersion: String

    public init(deviceName: String, deviceID: String, appVersion: String) {
        self.deviceName = deviceName
        self.deviceID = deviceID
        self.appVersion = appVersion
    }

    public func makeClient(serverURL: URL, accessToken: String? = nil) -> JellyfinClient {
        JellyfinClient(
            configuration: .init(
                url: serverURL,
                accessToken: accessToken,
                client: Self.clientName,
                deviceName: deviceName,
                deviceID: deviceID,
                version: appVersion,
            ),
        )
    }
}
