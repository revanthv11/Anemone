import Foundation

/// `NOTICE.md`, read for the in-app licenses screen, as Wholphin's `LicenseInfo` lists the
/// libraries it's built on.
///
/// The app bundles the repo's own `NOTICE.md` at build time, so every credit added there shows
/// up in Settings › About without touching the screen. Only the Markdown that file uses is
/// understood: `##` sections, paragraphs, `-` lists, `###` headings and tables. HTML comments
/// are notes for maintainers and are skipped.
public struct Notice: Equatable, Sendable {
    public var sections: [Section]

    public struct Section: Equatable, Sendable, Identifiable {
        public var title: String
        public var blocks: [Block]

        public var id: String {
            title
        }

        public init(title: String, blocks: [Block]) {
            self.title = title
            self.blocks = blocks
        }

        /// The packages credited in this section's tables.
        public var packages: [Package] {
            blocks.flatMap { block -> [Package] in
                guard case let .table(table) = block else { return [] }
                return table.packages
            }
        }
    }

    /// Inline Markdown (bold, code, links) is left in the text for the view to render.
    public enum Block: Equatable, Sendable {
        case heading(String)
        case paragraph(String)
        case list([String])
        case table(Table)
    }

    public struct Table: Equatable, Sendable {
        public var header: [String]
        public var rows: [[String]]

        public init(header: [String], rows: [[String]]) {
            self.header = header
            self.rows = rows
        }

        /// One package per link in the "Package" column of a table that also has a "License"
        /// column, as in NOTICE.md's "Third-party packages". A row such as
        /// `[swift-nio](…), [swift-system](…) (via …)` credits each package it links.
        public var packages: [Package] {
            let columns = header.map { $0.lowercased() }
            guard let nameColumn = columns.firstIndex(of: "package"),
                  let licenseColumn = columns.firstIndex(of: "license")
            else { return [] }
            return rows.flatMap { row -> [Package] in
                guard row.indices.contains(nameColumn), row.indices.contains(licenseColumn) else { return [] }
                return Package.all(in: row[nameColumn], license: row[licenseColumn])
            }
        }
    }

    public struct Package: Equatable, Sendable, Identifiable {
        public var name: String
        public var url: URL?
        /// The license as NOTICE.md names it, usually an SPDX identifier such as `MIT`.
        public var license: String
        /// What else the row says, such as "via jellyfin-sdk-swift".
        public var note: String?

        public var id: String {
            name
        }

        public init(name: String, url: URL?, license: String, note: String? = nil) {
            self.name = name
            self.url = url
            self.license = license
            self.note = note
        }

        static func all(in cell: String, license: String) -> [Package] {
            let links = Notice.links(in: cell)
            let license = Notice.plainText(license)
            guard !links.isEmpty else {
                let name = Notice.plainText(cell)
                return name.isEmpty ? [] : [Package(name: name, url: nil, license: license)]
            }
            var rest = cell
            for link in links {
                rest = rest.replacingOccurrences(of: link.markdown, with: "")
            }
            let note = rest
                .trimmingCharacters(in: CharacterSet(charactersIn: " ,;()"))
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
            return links.map { link in
                Package(
                    name: Notice.plainText(link.text),
                    url: URL(string: link.destination),
                    license: license,
                    note: note.isEmpty ? nil : note,
                )
            }
        }
    }

    public init(sections: [Section]) {
        self.sections = sections
    }

    public init(markdown: String) {
        var parser = Parser()
        for line in Self.withoutComments(markdown).components(separatedBy: .newlines) {
            parser.read(line)
        }
        sections = parser.finish()
    }

    /// Every package credited in a table, in the order NOTICE.md lists them.
    public var packages: [Package] {
        sections.flatMap(\.packages)
    }

    /// `text` with each link written out as `text (example.com/path)`, since a TV can't follow
    /// links: the screen shows where each credit comes from instead.
    public static func showingLinks(_ text: String) -> String {
        var result = text
        for link in links(in: text) {
            let shown = link.destination
                .replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")
            result = result.replacingOccurrences(of: link.markdown, with: "\(link.text) (\(shown))")
        }
        return result
    }

    /// `text` without Markdown: link text stays, link targets, `*` and `` ` `` go.
    public static func plainText(_ text: String) -> String {
        var result = text
        for link in links(in: text) {
            result = result.replacingOccurrences(of: link.markdown, with: link.text)
        }
        return result
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    struct Link {
        var markdown: String
        var text: String
        var destination: String
    }

    /// The inline links `[text](destination)` in `text`, in order.
    static func links(in text: String) -> [Link] {
        var links: [Link] = []
        var remaining = text[...]
        while let open = remaining.firstIndex(of: "[") {
            guard let close = remaining[open...].firstIndex(of: "]"),
                  remaining.index(after: close) < remaining.endIndex,
                  remaining[remaining.index(after: close)] == "(",
                  let end = remaining[close...].firstIndex(of: ")")
            else {
                remaining = remaining[remaining.index(after: open)...]
                continue
            }
            let linkText = remaining[remaining.index(after: open) ..< close]
            let destination = remaining[remaining.index(close, offsetBy: 2) ..< end]
            links.append(Link(
                markdown: String(remaining[open ... end]),
                text: String(linkText),
                destination: String(destination),
            ))
            remaining = remaining[remaining.index(after: end)...]
        }
        return links
    }

    private static func withoutComments(_ markdown: String) -> String {
        var result = ""
        var remaining = markdown[...]
        while let start = remaining.range(of: "<!--") {
            result += remaining[..<start.lowerBound]
            guard let end = remaining[start.upperBound...].range(of: "-->") else {
                return result
            }
            remaining = remaining[end.upperBound...]
        }
        return result + remaining
    }
}

/// Reads NOTICE.md a line at a time.
private struct Parser {
    private var sections: [Notice.Section] = []
    private var title = ""
    private var blocks: [Notice.Block] = []
    private var paragraph: [String] = []
    private var items: [String] = []
    private var tableLines: [String] = []

    mutating func read(_ rawLine: String) {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("## ") {
            endSection()
            title = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("# ") {
            // The document's own title ("Notice"); the screen has its own.
            endBlock()
        } else if line.hasPrefix("### ") {
            endBlock()
            blocks.append(.heading(String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)))
        } else if line.isEmpty {
            endBlock()
        } else if line.hasPrefix("|") {
            if tableLines.isEmpty {
                endBlock()
            }
            tableLines.append(line)
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            if items.isEmpty {
                endBlock()
            }
            items.append(String(line.dropFirst(2)))
        } else if !items.isEmpty, rawLine.hasPrefix(" ") {
            // A list item continued on the next, indented line.
            items[items.count - 1] += " " + line
        } else {
            if !items.isEmpty || !tableLines.isEmpty {
                endBlock()
            }
            paragraph.append(line)
        }
    }

    mutating func finish() -> [Notice.Section] {
        endSection()
        return sections
    }

    private mutating func endSection() {
        endBlock()
        if !blocks.isEmpty {
            sections.append(Notice.Section(title: title, blocks: blocks))
        }
        title = ""
        blocks = []
    }

    private mutating func endBlock() {
        if !paragraph.isEmpty {
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph = []
        }
        if !items.isEmpty {
            blocks.append(.list(items))
            items = []
        }
        if !tableLines.isEmpty {
            if let table = Self.table(tableLines) {
                blocks.append(.table(table))
            }
            tableLines = []
        }
    }

    /// A header row, the `|---|` separator, then the rows.
    private static func table(_ lines: [String]) -> Notice.Table? {
        let rows = lines.map(cells).filter { row in
            !row.allSatisfy { cell in !cell.isEmpty && cell.allSatisfy { "-: ".contains($0) } }
        }
        guard let header = rows.first else { return nil }
        return Notice.Table(header: header, rows: Array(rows.dropFirst()))
    }

    private static func cells(_ line: String) -> [String] {
        var text = line[...]
        if text.hasPrefix("|") {
            text = text.dropFirst()
        }
        if text.hasSuffix("|") {
            text = text.dropLast()
        }
        return text.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
