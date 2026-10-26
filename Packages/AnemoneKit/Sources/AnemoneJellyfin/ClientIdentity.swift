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

    /// - Parameter deviceName: the Apple TV's name. The SDK writes the `Authorization` header
    ///   fields without quoting or escaping, so the name is reduced to printable ASCII (`’` → `'`,
    ///   `ä` → `a`) and commas, quotes and `=` become spaces.
    public init(deviceName: String, deviceID: String, appVersion: String) {
        self.deviceName = Self.headerSafe(deviceName)
        self.deviceID = deviceID
        self.appVersion = appVersion
    }

    static func headerSafe(_ name: String) -> String {
        let ascii = name.applyingTransform(StringTransform("Any-Latin; Latin-ASCII"), reverse: false) ?? name
        let separators: Set<Character> = [",", "\"", "="]
        let cleaned = ascii.compactMap { character -> Character? in
            guard character.isASCII, !character.isNewline, character.asciiValue.map({ $0 >= 0x20 }) == true else {
                return nil
            }
            return separators.contains(character) ? " " : character
        }
        let trimmed = String(cleaned).trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Apple TV" : trimmed
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
