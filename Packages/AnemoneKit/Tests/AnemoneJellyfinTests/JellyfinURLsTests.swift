import AnemoneJellyfin
import Foundation
import Testing

struct JellyfinURLsTests {
    @Test func `builds user image URLs under a reverse-proxy path`() throws {
        let server = try #require(URL(string: "https://demo.jellyfin.org/stable"))

        let url = JellyfinURLs.userImage(on: server, userID: "u1", tag: "abc")

        #expect(url?.absoluteString == "https://demo.jellyfin.org/stable/UserImage?userId=u1&tag=abc")
    }

    @Test func `builds item image URLs with a size and tag`() throws {
        let server = try #require(URL(string: "https://tv.test/jf"))

        let url = JellyfinURLs.itemImage(
            on: server,
            image: ItemImage(itemID: "i1", kind: .thumb, tag: "t1"),
            maxWidth: 640,
        )

        #expect(url?.absoluteString == "https://tv.test/jf/Items/i1/Images/Thumb?maxWidth=640&quality=96&tag=t1")
    }
}
