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

    /// - Parameter deviceName: the Apple TV's name. Commas, quotes and `=` are replaced, because
    ///   the SDK writes the `Authorization` header fields without quoting or escaping them.
    public init(deviceName: String, deviceID: String, appVersion: String) {
        let unsafe: Set<Character> = [",", "\"", "="]
        self.deviceName = String(deviceName.map { unsafe.contains($0) ? " " : $0 })
        self.deviceID = deviceID
        self.appVersion = appVersion
    }

    public func makeClient(
        serverURL: URL,
        accessToken: String? = nil,
        sessionConfiguration: URLSessionConfiguration = .default,
    ) -> JellyfinClient {
        JellyfinClient(
            configuration: .init(
                url: serverURL,
                accessToken: accessToken,
                client: Self.clientName,
                deviceName: deviceName,
                deviceID: deviceID,
                version: appVersion,
            ),
            sessionConfiguration: sessionConfiguration,
        )
    }
}
