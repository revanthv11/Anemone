import AnemoneCore
import Foundation
import Testing

/// Builds without Seerr leave its credits out of Settings › About.
struct NoticeLeavingOutTests {
    private let notice = Notice(markdown: """
    ## Wholphin

    Anemone is a modified version of Wholphin.

    ## Seerr

    The Seerr client is generated from Seerr's API description.

    - Licensed under the MIT License

    ## Third-party packages

    | Package | License |
    |---|---|
    | [Nuke](https://github.com/kean/Nuke) | MIT |
    | [swift-openapi-runtime](https://github.com/apple/swift-openapi-runtime), \
    [swift-http-types](https://github.com/apple/swift-http-types) (the Seerr client's) | Apache-2.0 |
    | [swift-collections](https://github.com/apple/swift-collections), \
    [swift-http-types](https://github.com/apple/swift-http-types) (via something else) | Apache-2.0 |
    """)

    @Test func `the named sections and the rows crediting only named packages are left out`() {
        let shown = notice.leavingOut(["Seerr", "swift-openapi-runtime", "swift-http-types"])

        #expect(shown.sections.map(\.title) == ["Wholphin", "Third-party packages"])
        // A row that also credits a package the build keeps stays whole.
        #expect(shown.packages.map(\.name) == ["Nuke", "swift-collections", "swift-http-types"])
    }

    @Test func `leaving out nothing keeps everything`() {
        #expect(notice.leavingOut([]) == notice)
        #expect(notice.sections.map(\.title) == ["Wholphin", "Seerr", "Third-party packages"])
    }
}
