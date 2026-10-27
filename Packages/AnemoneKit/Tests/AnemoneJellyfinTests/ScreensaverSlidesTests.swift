@testable import AnemoneJellyfin
import Foundation
import Testing

struct ScreensaverSlidesTests {
    @Test func `asks for random movies and series with a backdrop, up to the age rating`() async throws {
        let server = HomeServer("screensaver-request.test") { path, _ in
            path == "/Items" ? .homeItems() : nil
        }

        _ = try await server.session().screensaverSlides(maxAgeRating: 16)

        let sent = try #require(server.requests(to: "/Items").first)
        #expect(sent.method == "GET")
        #expect(sent.query["userId"] == "u1")
        #expect(sent.query["recursive"] == "true")
        #expect(sent.query["includeItemTypes"] == "Movie,Series")
        #expect(sent.query["imageTypes"] == "Backdrop")
        #expect(sent.query["sortBy"] == "Random")
        #expect(sent.query["maxOfficialRating"] == "16")
        #expect(sent.query["hasParentalRating"] == "true")
        #expect(sent.query["limit"] == "100")
    }

    @Test func `any rating leaves the rating out`() async throws {
        let server = HomeServer("screensaver-anyrating.test") { path, _ in
            path == "/Items" ? .homeItems() : nil
        }

        _ = try await server.session().screensaverSlides(maxAgeRating: nil)

        let sent = try #require(server.requests(to: "/Items").first)
        #expect(sent.query["maxOfficialRating"] == nil)
        #expect(sent.query["hasParentalRating"] == nil)
    }

    @Test func `each slide is a backdrop with a logo when there is one`() async throws {
        let server = HomeServer("screensaver-slides.test") { path, _ in
            guard path == "/Items" else { return nil }
            return .homeItems(
                #"{"Id":"m1","Name":"Dracula","Type":"Movie","BackdropImageTags":["b1"],"ImageTags":{"Logo":"l1"}}"#,
                #"{"Id":"s1","Name":"Pioneer One","Type":"Series","BackdropImageTags":["b2","b3"]}"#,
                #"{"Id":"m2","Name":"No Backdrop","Type":"Movie"}"#,
            )
        }

        let slides = try await server.session().screensaverSlides(maxAgeRating: nil)

        #expect(slides == [
            ScreensaverSlide(
                id: "m1",
                title: "Dracula",
                backdrop: ItemImage(itemID: "m1", kind: .backdrop, tag: "b1"),
                logo: ItemImage(itemID: "m1", kind: .logo, tag: "l1"),
            ),
            ScreensaverSlide(
                id: "s1",
                title: "Pioneer One",
                backdrop: ItemImage(itemID: "s1", kind: .backdrop, tag: "b2"),
            ),
        ])
    }
}
