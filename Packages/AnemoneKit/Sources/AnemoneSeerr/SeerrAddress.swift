#if ANEMONE_SEERR
    import Foundation

    /// Turning what the user typed into the addresses to try, and an address into the API's.
    /// Ported from Wholphin's `createUrls` and `createSeerrApiUrl` (`SwitchSeerrViewModel.kt`).
    public enum SeerrAddress {
        /// Seerr's own port, tried when the address doesn't name one.
        public static let defaultPort = 5055

        /// The addresses to try for what the user typed, in order. Like Wholphin, an address
        /// without a port is also tried on Seerr's port 5055.
        ///
        /// Changed from Wholphin: without a scheme, HTTPS is tried before plain HTTP at each port,
        /// as Anemone's add-server does for Jellyfin, so a server reachable both ways is saved
        /// with HTTPS. Wholphin tries HTTP first.
        ///
        /// - Throws: `SeerrError.invalidAddress` when it isn't an address.
        public static func candidates(for typed: String) throws(SeerrError) -> [URL] {
            let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowercased = text.lowercased()
            if lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://") {
                let address = try Parsed(text)
                var urls = [address.url]
                if address.isDefaultPort {
                    urls.append(address.with(port: defaultPort).url)
                }
                return urls
            }
            let address = try Parsed("http://" + text)
            if address.port == 80 {
                let https = address.with(scheme: "https", port: 443)
                return [
                    https.url,
                    address.url,
                    https.with(port: defaultPort).url,
                    address.with(port: defaultPort).url,
                ]
            }
            return [address.with(scheme: "https").url, address.url]
        }

        /// The API's base address for a server: its address with `api/v1` added, unless it's
        /// there already. Without a trailing slash, since the client adds each endpoint's path to
        /// it (Wholphin keeps one if the user typed it).
        public static func apiURL(for server: URL) -> URL {
            var text = server.absoluteString
            while text.hasSuffix("/") {
                text.removeLast()
            }
            if !text.hasSuffix("/api/v1") {
                text += "/api/v1"
            }
            return URL(string: text) ?? server
        }

        /// A parsed address, normalized as OkHttp's `HttpUrl` prints it in Wholphin: the default
        /// port left out and an empty path written as `/`.
        private struct Parsed {
            var scheme: String
            var host: String
            var port: Int
            var path: String
            var query: String?

            init(_ text: String) throws(SeerrError) {
                guard let components = URLComponents(string: text),
                      let scheme = components.scheme?.lowercased(),
                      let host = components.host, !host.isEmpty
                else { throw .invalidAddress }
                self.scheme = scheme
                self.host = host
                port = components.port ?? Self.defaultPort(for: scheme)
                path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
                query = components.percentEncodedQuery
            }

            var isDefaultPort: Bool {
                port == Self.defaultPort(for: scheme)
            }

            func with(scheme: String? = nil, port: Int? = nil) -> Parsed {
                var copy = self
                if let scheme {
                    copy.scheme = scheme
                }
                if let port {
                    copy.port = port
                }
                return copy
            }

            var url: URL {
                var components = URLComponents()
                components.scheme = scheme
                components.host = host
                components.port = isDefaultPort ? nil : port
                components.percentEncodedPath = path
                components.percentEncodedQuery = query
                // Built from parts that parsed, so it always makes a URL.
                return components.url!
            }

            private static func defaultPort(for scheme: String) -> Int {
                scheme == "https" ? 443 : 80
            }
        }
    }
#endif
