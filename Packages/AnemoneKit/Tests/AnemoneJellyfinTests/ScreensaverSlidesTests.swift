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

    @Test func `with photos included, the backdrop isn't asked of the server`() async throws {
        let server = HomeServer("screensaver-photos.test") { path, _ in
            path == "/Items" ? .homeItems() : nil
        }

        _ = try await server.session().screensaverSlides(
            maxAgeRating: nil,
            types: ScreensaverItemTypes([.photo, .series]),
        )

        let sent = try #require(server.requests(to: "/Items").first)
        #expect(sent.query["includeItemTypes"] == "Series,Photo")
        #expect(sent.query["imageTypes"] == nil)
        #expect(sent.query["enableImageTypes"] == "Backdrop,Logo,Primary")
    }

    @Test func `with no types, nothing is asked and there's nothing to show`() async throws {
        let server = HomeServer("screensaver-notypes.test") { path, _ in
            path == "/Items" ? .homeItems() : nil
        }

        let slides = try await server.session().screensaverSlides(maxAgeRating: nil, types: ScreensaverItemTypes([]))

        #expect(slides.isEmpty)
        #expect(server.requests(to: "/Items").isEmpty)
    }

    @Test func `a photo is its own picture, titled with the day it was taken`() async throws {
        let server = HomeServer("screensaver-photo-slide.test") { path, _ in
            guard path == "/Items" else { return nil }
            return .homeItems(
                #"{"Id":"p1","Name":"IMG_0001.jpg","Type":"Photo","ImageTags":{"Primary":"t1"},"#
                    + #""PremiereDate":"2024-07-04T00:00:00.0000000Z"}"#,
                #"{"Id":"p2","Name":"IMG_0002.jpg","Type":"Photo","ImageTags":{"Primary":"t2"}}"#,
                #"{"Id":"m2","Name":"No Backdrop","Type":"Movie"}"#,
            )
        }

        let slides = try await server.session().screensaverSlides(
            maxAgeRating: nil,
            types: ScreensaverItemTypes([.movie, .photo]),
        )

        #expect(slides.map(\.id) == ["p1", "p2"])
        #expect(slides.first?.backdrop == ItemImage(itemID: "p1", kind: .primary, tag: "t1"))
        #expect(slides.first?.logo == nil)
        #expect(slides.first?.title.contains("2024") == true)
        #expect(slides.last?.title == "")
    }

    @Test func `the types are stored as the server's names, unknown ones dropped`() {
        #expect(ScreensaverItemTypes([.photo, .movie]).rawValue == "Movie,Photo")
        #expect(ScreensaverItemTypes(rawValue: "Series, Photo,Book")?.kinds == [.series, .photo])
        #expect(ScreensaverItemTypes(rawValue: "")?.kinds == [])
        var types = ScreensaverItemTypes.default
        types.set(.photo, included: true)
        types.set(.movie, included: false)
        #expect(types.rawValue == "Series,Photo")
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
