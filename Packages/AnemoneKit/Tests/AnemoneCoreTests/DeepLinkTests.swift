import AnemoneCore
import Foundation
import Testing

struct DeepLinkTests {
    private let itemID = "c541e7545e58b28cd4d0da7aac89d7e8"

    @Test func `an item link opens the item`() throws {
        let link = try #require(DeepLink(url: url("anemone://item/\(itemID)")))

        #expect(link == DeepLink(.item(id: itemID)))
    }

    @Test func `a play link plays from where it was left off unless it gives a position`() {
        #expect(DeepLink(url: url("anemone://play/\(itemID)")) == DeepLink(.play(id: itemID, position: nil)))
        #expect(DeepLink(url: url("anemone://play/\(itemID)?position=90500"))
            == DeepLink(.play(id: itemID, position: .milliseconds(90500))))
        // Wholphin clamps a negative position to the start.
        #expect(DeepLink(url: url("anemone://play/\(itemID)?position=-5"))
            == DeepLink(.play(id: itemID, position: .zero)))
    }

    @Test func `a search link searches for its query`() {
        #expect(DeepLink(url: url("anemone://search?query=St.%20Louis")) == DeepLink(.search("St. Louis")))
        #expect(DeepLink(url: url("anemone://search?q=llama")) == DeepLink(.search("llama")))
        #expect(DeepLink(url: url("anemone://search")) == DeepLink(.search("")))
    }

    @Test func `a link can name the profile it's for`() {
        let link = DeepLink(url: url("anemone://item/\(itemID)?server=srv1&user=abc-123"))

        #expect(link == DeepLink(.item(id: itemID), serverID: "srv1", userID: "abc-123"))
    }

    @Test func `reads Wholphin's parameter names`() {
        let link = DeepLink(url: url("ANEMONE://view?itemId=\(itemID)&serverId=srv1&userId=usr1"))

        #expect(link == DeepLink(.item(id: itemID), serverID: "srv1", userID: "usr1"))
    }

    @Test func `refuses other schemes, unknown actions and bad IDs`() {
        #expect(DeepLink(url: url("https://item/\(itemID)")) == nil)
        #expect(DeepLink(url: url("anemone://library/\(itemID)")) == nil)
        #expect(DeepLink(url: url("anemone://item")) == nil)
        #expect(DeepLink(url: url("anemone://play/")) == nil)
        #expect(DeepLink(url: url("anemone://item/..%2F..%2FUsers")) == nil)
        #expect(DeepLink(url: url("anemone://item/abc?def")) == DeepLink(.item(id: "abc")))
        #expect(DeepLink(url: url("anemone://item/\(String(repeating: "a", count: 65))")) == nil)
    }

    @Test func `a bad profile ID is dropped, not the link`() {
        let link = DeepLink(url: url("anemone://item/\(itemID)?server=a/b&user=usr1"))

        #expect(link == DeepLink(.item(id: itemID), userID: "usr1"))
    }

    @Test(arguments: [
        DeepLink(.item(id: "c541e7545e58b28cd4d0da7aac89d7e8")),
        DeepLink(.play(id: "abc", position: nil), serverID: "srv", userID: "usr"),
        DeepLink(.play(id: "abc", position: .milliseconds(1500))),
        DeepLink(.search("Night of the Living Dead & more")),
    ])
    func `links round-trip through their URL`(link: DeepLink) {
        #expect(DeepLink(url: link.url) == link)
    }

    @Test func `builds the URLs the Top Shelf uses`() {
        let link = DeepLink(.play(id: itemID, position: nil), serverID: "srv1", userID: "usr1")

        #expect(link.url.absoluteString == "anemone://play/\(itemID)?server=srv1&user=usr1")
    }

    private func url(_ text: String) -> URL {
        URL(string: text) ?? URL(fileURLWithPath: "/")
    }
}
