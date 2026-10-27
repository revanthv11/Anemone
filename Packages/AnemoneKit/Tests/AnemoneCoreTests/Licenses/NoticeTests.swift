import AnemoneCore
import Foundation
import Testing

struct NoticeTests {
    private let sample = """
    # Notice

    ## Wholphin

    Anemone is a modified version of [Wholphin](https://github.com/damontecres/Wholphin), an
    Android TV client for Jellyfin.

    - Copyright (C) Damontecres and Wholphin contributors
    - Licensed under the GNU General Public License, version 2
      or (at your option) any later version

    **Parity baseline:** `52c26bc`.

    ### Device profiles

    Adapted from jellyfin-androidtv.

    ## Third-party packages

    | Package | License |
    |---|---|
    | [Nuke](https://github.com/kean/Nuke) | MIT |
    | [swift-nio](https://github.com/apple/swift-nio), [swift-system](https://github.com/apple/swift-system) \
    (via swift-nio-transport-services) | Apache-2.0 |
    | Something unlinked | `BSD-3-Clause` |

    <!-- Update this table whenever a dependency is added. -->
    """

    @Test func `reads sections, paragraphs, lists and headings`() throws {
        let notice = Notice(markdown: sample)

        #expect(notice.sections.map(\.title) == ["Wholphin", "Third-party packages"])
        let wholphin = try #require(notice.sections.first)
        #expect(wholphin.blocks == [
            .paragraph(
                "Anemone is a modified version of [Wholphin](https://github.com/damontecres/Wholphin), an "
                    + "Android TV client for Jellyfin.",
            ),
            .list([
                "Copyright (C) Damontecres and Wholphin contributors",
                "Licensed under the GNU General Public License, version 2 or (at your option) any later version",
            ]),
            .paragraph("**Parity baseline:** `52c26bc`."),
            .heading("Device profiles"),
            .paragraph("Adapted from jellyfin-androidtv."),
        ])
    }

    @Test func `skips maintainer comments`() throws {
        let packagesSection = try #require(Notice(markdown: sample).sections.last)

        #expect(packagesSection.blocks.count == 1)
        guard case .table = packagesSection.blocks.first else {
            Issue.record("Expected only the table, got \(packagesSection.blocks)")
            return
        }
    }

    @Test func `credits each linked package in a table row`() {
        let packages = Notice(markdown: sample).packages

        #expect(packages == [
            Notice.Package(name: "Nuke", url: URL(string: "https://github.com/kean/Nuke"), license: "MIT"),
            Notice.Package(
                name: "swift-nio",
                url: URL(string: "https://github.com/apple/swift-nio"),
                license: "Apache-2.0",
                note: "via swift-nio-transport-services",
            ),
            Notice.Package(
                name: "swift-system",
                url: URL(string: "https://github.com/apple/swift-system"),
                license: "Apache-2.0",
                note: "via swift-nio-transport-services",
            ),
            Notice.Package(name: "Something unlinked", url: nil, license: "BSD-3-Clause"),
        ])
    }

    @Test func `ignores tables without package and license columns`() {
        let notice = Notice(markdown: """
        ## Other

        | Name | Role |
        |---|---|
        | [Someone](https://example.com) | Translator |
        """)

        #expect(notice.sections.count == 1)
        #expect(notice.packages.isEmpty)
    }

    @Test func `writes links out for a screen that can't follow them`() {
        let text = "A port of [Wholphin](https://github.com/damontecres/Wholphin) and [x](http://example.com/a)."

        #expect(
            Notice.showingLinks(text)
                == "A port of Wholphin (github.com/damontecres/Wholphin) and x (example.com/a).",
        )
        #expect(Notice.plainText("**[`Nuke`](https://github.com/kean/Nuke)**") == "Nuke")
    }

    @Test func `leaves unfinished links and comments alone`() {
        let notice = Notice(markdown: "## A\n\nSee [this] (not a link) and [that](\n\n<!-- open comment")

        #expect(notice.sections == [
            Notice.Section(title: "A", blocks: [.paragraph("See [this] (not a link) and [that](")]),
        ])
    }

    /// The repo's own NOTICE.md, which the app bundles: it must keep parsing into the credits the
    /// licenses screen promises, whatever other changes add to it.
    @Test func `the repo's NOTICE.md credits Wholphin, Swiftfin, the SDKs and Nuke`() throws {
        let root = URL(filePath: #filePath)
            .deletingLastPathComponent() // Licenses
            .deletingLastPathComponent() // AnemoneCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // AnemoneKit
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent()
        let markdown = try String(contentsOf: root.appending(path: "NOTICE.md"), encoding: .utf8)
        let notice = Notice(markdown: markdown)

        let titles = notice.sections.map(\.title)
        #expect(titles.contains("Wholphin"))
        #expect(titles.contains("Swiftfin"))
        func license(of name: String) -> String? {
            notice.packages.first { $0.name == name }?.license
        }
        #expect(license(of: "jellyfin-sdk-swift") == "MPL-2.0")
        #expect(license(of: "Nuke") == "MIT")
        #expect(license(of: "Get") == "MIT")
        #expect(notice.packages.allSatisfy { $0.url != nil })
    }
}
