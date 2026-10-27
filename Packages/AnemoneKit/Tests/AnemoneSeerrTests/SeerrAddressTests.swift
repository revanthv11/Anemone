#if ANEMONE_SEERR
    @testable import AnemoneSeerr
    import Foundation
    import Testing

    /// Ported from Wholphin's `TestSeerr`, with HTTPS tried before HTTP when no scheme is typed.
    struct SeerrAddressTests {
        private func candidates(_ typed: String) throws -> [String] {
            try SeerrAddress.candidates(for: typed).map(\.absoluteString)
        }

        @Test func `a bare host is tried with both schemes on its default port and on 5055`() throws {
            #expect(try candidates("jellyseerr.com") == [
                "https://jellyseerr.com/",
                "http://jellyseerr.com/",
                "https://jellyseerr.com:5055/",
                "http://jellyseerr.com:5055/",
            ])
        }

        @Test func `an address with a scheme keeps it and is also tried on 5055`() throws {
            #expect(try candidates("https://jellyseerr.com") == [
                "https://jellyseerr.com/",
                "https://jellyseerr.com:5055/",
            ])
            #expect(try candidates("http://jellyseerr.com") == [
                "http://jellyseerr.com/",
                "http://jellyseerr.com:5055/",
            ])
        }

        @Test func `a host with a port keeps the port`() throws {
            #expect(try candidates("jellyseerr.com:5055") == [
                "https://jellyseerr.com:5055/",
                "http://jellyseerr.com:5055/",
            ])
            #expect(try candidates("10.0.0.2:8080") == [
                "https://10.0.0.2:8080/",
                "http://10.0.0.2:8080/",
            ])
        }

        @Test func `a default port is written as OkHttp writes it`() throws {
            #expect(try candidates("10.0.0.2:443") == [
                "https://10.0.0.2/",
                "http://10.0.0.2:443/",
            ])
            #expect(try candidates("http://10.0.0.2:80") == [
                "http://10.0.0.2/",
                "http://10.0.0.2:5055/",
            ])
            #expect(try candidates("https://10.0.0.2:443") == [
                "https://10.0.0.2/",
                "https://10.0.0.2:5055/",
            ])
        }

        @Test func `a path is kept on every address`() throws {
            #expect(try candidates("https://jellyseerr.com/seerr/") == [
                "https://jellyseerr.com/seerr/",
                "https://jellyseerr.com:5055/seerr/",
            ])
        }

        @Test func `something that isn't an address is refused`() {
            #expect(throws: SeerrError.invalidAddress) {
                try SeerrAddress.candidates(for: "")
            }
            #expect(throws: SeerrError.invalidAddress) {
                try SeerrAddress.candidates(for: "http://")
            }
        }

        @Test func `the API is under api v1 of the server's address`() throws {
            func api(_ text: String) throws -> String {
                try SeerrAddress.apiURL(for: #require(URL(string: text))).absoluteString
            }
            #expect(try api("https://jellyseerr.com/") == "https://jellyseerr.com/api/v1")
            #expect(try api("https://jellyseerr.com/path") == "https://jellyseerr.com/path/api/v1")
            #expect(try api("http://jellyseerr.com:5055/") == "http://jellyseerr.com:5055/api/v1")
            #expect(try api("http://jellyseerr.com:7878/path/") == "http://jellyseerr.com:7878/path/api/v1")
            #expect(try api("http://jellyseerr.com/api/v1") == "http://jellyseerr.com/api/v1")
            // Wholphin keeps this trailing slash; the generated client adds paths that start with one.
            #expect(try api("http://jellyseerr.com/api/v1/") == "http://jellyseerr.com/api/v1")
            #expect(try api("http://jellyseerr.com/path/api/v1") == "http://jellyseerr.com/path/api/v1")
        }
    }
#endif
