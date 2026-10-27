import AnemoneCore
import AnemoneUI
import SwiftUI

/// One project Anemone is based on or adapts code from, such as Wholphin or Swiftfin, as its
/// NOTICE.md section tells it, then that project's full license when the app has it.
struct CreditPage: View {
    let section: Notice.Section

    var body: some View {
        ReadingPage(title: section.title) {
            ForEach(Array(section.blocks.enumerated()), id: \.offset) { _, block in
                rows(for: block)
            }
            if BundledLicenses.licenseText(for: section.title) != nil {
                NavigationLink("\(section.title)'s license") {
                    LicenseTextPage(title: "\(section.title)'s license", licenseName: section.title)
                }
                .padding(.top, 24)
                .accessibilityIdentifier("credit.license")
            }
        }
    }

    @ViewBuilder
    private func rows(for block: Notice.Block) -> some View {
        switch block {
        case let .heading(text):
            ReadingRow {
                MarkdownText(text)
                    .font(.headline)
            }
        case let .paragraph(text):
            ReadingRow {
                MarkdownText(text)
            }
        case let .list(items):
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                ReadingRow {
                    HStack(alignment: .firstTextBaseline, spacing: 20) {
                        Text("•")
                        MarkdownText(item)
                    }
                }
            }
        case let .table(table):
            ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                ReadingRow {
                    MarkdownText(row.joined(separator: " · "))
                }
            }
        }
    }
}

/// A package from NOTICE.md's table: its license, where it comes from, and the license's text.
struct PackagePage: View {
    let package: Notice.Package

    @Environment(\.theme) private var theme

    var body: some View {
        ReadingPage(title: package.name) {
            ReadingRow {
                LabeledContent("License", value: package.license)
            }
            if let url = package.url {
                ReadingRow {
                    LabeledContent("Source", value: "\(url.host() ?? "")\(url.path())")
                }
            }
            if let note = package.note {
                ReadingRow {
                    Text(note)
                        .foregroundStyle(theme.secondaryText)
                }
            }
            if let text = BundledLicenses.licenseText(for: package.name) {
                Text("License text")
                    .font(.headline)
                    .foregroundStyle(theme.secondaryText)
                    .padding(.top, 24)
                    .accessibilityAddTraits(.isHeader)
                LicenseParagraphs(text: text)
            }
        }
    }
}

/// A license's full text on its own page, such as Anemone's GPL.
struct LicenseTextPage: View {
    let title: String
    /// The `LICENSE-<name>.txt` to show.
    let licenseName: String

    @Environment(\.theme) private var theme

    var body: some View {
        ReadingPage(title: title) {
            if let text = BundledLicenses.licenseText(for: licenseName) {
                LicenseParagraphs(text: text)
            } else {
                ReadingRow {
                    Text("This build is missing the license's text.")
                        .foregroundStyle(theme.secondaryText)
                }
            }
        }
    }
}

/// A license's text a paragraph per row, so focus can step through it and the page scrolls.
private struct LicenseParagraphs: View {
    private let paragraphs: [String]

    init(text: String) {
        paragraphs = LicenseText.paragraphs(text)
    }

    var body: some View {
        ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
            ReadingRow {
                Text(paragraph)
                    .font(.callout)
            }
            .accessibilityIdentifier("license.paragraph.\(index)")
        }
    }
}

/// A page of text to read on a TV. A scroll view rather than a list, whose rows can't size
/// themselves to a long paragraph reliably. The title scrolls with the text: the navigation
/// bar's title stays put over a scroll view and the text would run under it.
private struct ReadingPage<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.title2.bold())
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    .accessibilityAddTraits(.isHeader)
                content
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 40)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// A row of text that takes focus, so the remote steps through the page and it scrolls, with
/// a soft highlight to show where focus is.
private struct ReadingRow<Content: View>: View {
    @ViewBuilder let content: Content

    @Environment(\.theme) private var theme
    @FocusState private var isFocused: Bool

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(isFocused ? theme.platter.color : .clear, in: .rect(cornerRadius: 12))
            .focusable()
            .focused($isFocused)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

/// NOTICE.md's inline Markdown (bold and code) with links written out, since a TV can't follow them.
struct MarkdownText: View {
    let markdown: String

    init(_ markdown: String) {
        self.markdown = markdown
    }

    var body: some View {
        let shown = Notice.showingLinks(markdown)
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        Text((try? AttributedString(markdown: shown, options: options)) ?? AttributedString(shown))
    }
}
