import AnemoneCore
import Foundation
import Testing

struct LibraryPinsTests {
    private let server = ["movies", "shows", "music", "photos"]

    @Test func `pins every library in the server's order by default`() {
        let (pinned, unpinned) = LibraryPins().arrange(server) { $0 }

        #expect(pinned == server)
        #expect(unpinned.isEmpty)
    }

    @Test func `moves unpinned libraries to More, keeping the user's order`() {
        var pins = LibraryPins()
        pins.move("photos", by: -1, in: server)
        pins.setPinned(false, "music")

        let (pinned, unpinned) = pins.arrange(server) { $0 }

        #expect(pinned == ["movies", "shows", "photos"])
        #expect(unpinned == ["music"])
        #expect(!pins.isPinned("music"))
    }

    @Test func `puts libraries added on the server later at the end, pinned`() {
        var pins = LibraryPins()
        pins.move("shows", by: -1, in: server)

        let (pinned, _) = pins.arrange(["new", "movies", "shows", "music", "photos"]) { $0 }

        #expect(pinned == ["shows", "movies", "music", "photos", "new"])
    }

    @Test func `skips libraries the user can no longer see`() {
        var pins = LibraryPins()
        pins.setPinned(false, "music")
        pins.move("photos", by: -1, in: server)

        let (pinned, unpinned) = pins.arrange(["photos", "movies"]) { $0 }

        #expect(pinned == ["movies", "photos"])
        #expect(unpinned.isEmpty)
    }

    @Test func `moving past either end does nothing`() {
        var pins = LibraryPins()
        pins.move("movies", by: -1, in: server)
        pins.move("photos", by: 1, in: server)

        #expect(pins == LibraryPins())
    }

    @Test func `pins survive a round trip through JSON`() throws {
        var pins = LibraryPins()
        pins.setPinned(false, "shows")
        pins.move("music", by: -1, in: server)

        let decoded = try JSONDecoder().decode(LibraryPins.self, from: JSONEncoder().encode(pins))

        #expect(decoded == pins)
    }
}
