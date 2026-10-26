import AnemoneCore
import Testing

struct ServerVersionTests {
    @Test(arguments: [
        ("12.3", ServerVersion(major: 12, minor: 3)),
        ("12.0.1", ServerVersion(major: 12, minor: 0, patch: 1)),
        ("10.11.2", ServerVersion(major: 10, minor: 11, patch: 2)),
        ("12.1.0-rc2", ServerVersion(major: 12, minor: 1)),
    ])
    func parses(string: String, expected: ServerVersion) {
        #expect(ServerVersion(string) == expected)
    }

    @Test(arguments: ["", "12", "abc", "12.x", ".3"])
    func `rejects malformed`(string: String) {
        #expect(ServerVersion(string) == nil)
    }

    @Test func `compares component wise`() {
        #expect(ServerVersion(major: 10, minor: 11) < ServerVersion(major: 12, minor: 0))
        #expect(ServerVersion(major: 12, minor: 0, patch: 9) < ServerVersion(major: 12, minor: 1))
    }

    @Test func `requires jellyfin 12`() {
        #expect(ServerVersion(major: 12, minor: 0).isSupported)
        #expect(ServerVersion(major: 12, minor: 3).isSupported)
        #expect(!ServerVersion(major: 10, minor: 11, patch: 2).isSupported)
    }
}
