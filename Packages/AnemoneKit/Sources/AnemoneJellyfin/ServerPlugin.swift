import AnemoneCore
import Foundation
import Get

/// The companion server plugin, [jellyfin-plugin-wholphin](https://github.com/damontecres/jellyfin-plugin-wholphin),
/// which lets admins set things up once for every user. Ported from Wholphin's `ServerPluginApi`
/// at `cecfdae`: a check that it's installed, and a GET per endpoint where a 404 means the plugin
/// isn't there or has nothing set up. Features add their endpoints in their own files.
///
/// jellyfin-sdk-swift 3.3.0 knows nothing of the plugin, so the requests are built by hand.
public extension JellyfinSession {
    /// Whether the server has the plugin. Any failure counts as no, as in Wholphin.
    func isServerPluginInstalled() async -> Bool {
        do {
            _ = try await client.data(for: Request<Void>(path: Self.pluginPath("public")))
            return true
        } catch {
            return false
        }
    }

    /// The home rows the plugin sets for every user, or `nil` when it sets none.
    ///
    /// - Throws: `HomeSettingsError.unsupportedVersion` for settings from a newer schema.
    func serverPluginHomePageSettings() async throws -> HomePageSettings? {
        let settings = try await serverPluginValue(HomePageSettings.self, path: "homesettings")
        return settings?.rows.isEmpty == false ? settings : nil
    }
}

extension JellyfinSession {
    /// GETs one of the plugin's endpoints, Wholphin's `executeRequest`. `nil` on a 404.
    func serverPluginValue<Value: Decodable>(_: Value.Type, path: String) async throws -> Value? {
        let data: Data
        do {
            data = try await client.data(for: Request<Void>(path: Self.pluginPath(path))).value
        } catch APIError.unacceptableStatusCode(404) {
            return nil
        } catch APIError.unacceptableStatusCode(401) {
            throw SessionError.signedOut
        }
        let decoder = JSONDecoder()
        // Wholphin reads the plugin's JSON leniently.
        decoder.allowsJSON5 = true
        return try decoder.decode(Value.self, from: data)
    }

    private static func pluginPath(_ path: String) -> String {
        "/wholphin/\(path)"
    }
}
