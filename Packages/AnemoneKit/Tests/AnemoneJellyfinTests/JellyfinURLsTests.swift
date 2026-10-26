import AnemoneJellyfin
import Foundation
import Testing

struct JellyfinURLsTests {
    @Test func `builds user image URLs under a reverse-proxy path`() throws {
        let server = try #require(URL(string: "https://demo.jellyfin.org/stable"))

        let url = JellyfinURLs.userImage(on: server, userID: "u1", tag: "abc")

        #expect(url?.absoluteString == "https://demo.jellyfin.org/stable/UserImage?userId=u1&tag=abc")
    }
}
