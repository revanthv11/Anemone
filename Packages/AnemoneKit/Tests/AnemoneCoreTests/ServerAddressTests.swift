import AnemoneCore
import Foundation
import Testing

struct ServerAddressTests {
    @Test(arguments: [
        ("https://jellyfin.example.com", ["https://jellyfin.example.com"]),
        ("http://10.0.0.5:8096/jf/", ["http://10.0.0.5:8096/jf"]),
        ("HTTPS://Media.Example.com", ["HTTPS://Media.Example.com"]),
        ("192.168.1.20:8096", ["https://192.168.1.20:8096", "http://192.168.1.20:8096"]),
        ("nas.local", ["https://nas.local", "http://nas.local:8096", "http://nas.local"]),
        ("  nas.local/jellyfin  ", [
            "https://nas.local/jellyfin", "http://nas.local:8096/jellyfin", "http://nas.local/jellyfin",
        ]),
    ])
    func `builds candidates`(input: String, expected: [String]) {
        #expect(ServerAddress.candidates(for: input).map(\.absoluteString) == expected)
    }

    @Test(arguments: ["", "   ", "nas local", "ftp://nas.local", "http://", ":8096"])
    func `rejects non-addresses`(input: String) {
        #expect(ServerAddress.candidates(for: input).isEmpty)
    }
}
