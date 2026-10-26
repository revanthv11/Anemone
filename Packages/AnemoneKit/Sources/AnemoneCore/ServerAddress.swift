import Foundation

/// Turns what someone typed into the "server address" field into URLs worth trying.
public enum ServerAddress {
    /// Jellyfin's default HTTP port.
    public static let defaultHTTPPort = 8096

    /// Candidate URLs for `input`, most likely first.
    ///
    /// - `https://jellyfin.example.com` or `http://10.0.0.5:8096/jf` are used as typed.
    /// - Without a scheme, HTTPS is tried before HTTP, and a bare host also gets Jellyfin's
    ///   default port: `nas.local` → `https://nas.local`, `http://nas.local:8096`, `http://nas.local`.
    ///
    /// Returns an empty array when `input` can't be a server address.
    public static func candidates(for input: String) -> [URL] {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return [] }

        let lowercased = trimmed.lowercased()
        if lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://") {
            return url(withoutTrailingSlashes(trimmed)).map { [$0] } ?? []
        }
        let text = withoutTrailingSlashes(trimmed)
        guard text.range(of: "://") == nil, let parsed = URLComponents(string: "http://\(text)"),
              parsed.host?.isEmpty == false
        else { return [] }

        let urls: [URL?] = if parsed.port != nil {
            [url("https://\(text)"), url("http://\(text)")]
        } else {
            [url("https://\(text)"), url(withPort: defaultHTTPPort, parsed), url("http://\(text)")]
        }
        return urls.compactMap(\.self)
    }

    private static func withoutTrailingSlashes(_ text: String) -> String {
        var text = text
        while text.hasSuffix("/") {
            text.removeLast()
        }
        return text
    }

    private static func url(_ string: String) -> URL? {
        guard let components = URLComponents(string: string), components.host?.isEmpty == false else { return nil }
        return components.url
    }

    private static func url(withPort port: Int, _ components: URLComponents) -> URL? {
        var components = components
        components.scheme = "http"
        components.port = port
        return components.url
    }
}
