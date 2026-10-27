import Foundation

/// A cue's text as SRT and WebVTT files write it: the bold and italic tags (`<b>`, `<i>`, and
/// ASS's `{\b1}` and `{\i1}`, which SRT converted from ASS keeps) become styled spans, `{\an8}`
/// and its neighbours move the cue to the top, and every other tag (colours, fonts, voices,
/// classes, karaoke times) is left out, as is ruby text. Entities such as `&amp;` are decoded.
enum SubtitleMarkup {
    struct Parsed: Equatable {
        var lines: [SubtitleLine]
        var placement: SubtitleCue.Placement
    }

    /// Lines that are empty once the tags are gone are left out.
    static func parse(_ text: String) -> Parsed {
        var parser = Parser(Array(text))
        parser.run()
        return Parsed(lines: parser.lines.compactMap(trimmed), placement: parser.placement)
    }

    /// The line without the spaces around it, or `nil` if nothing's left.
    private static func trimmed(_ line: SubtitleLine) -> SubtitleLine? {
        var spans = line.spans
        while let first = spans.first, first.text.allSatisfy(\.isWhitespace) {
            spans.removeFirst()
        }
        while let last = spans.last, last.text.allSatisfy(\.isWhitespace) {
            spans.removeLast()
        }
        guard !spans.isEmpty else { return nil }
        spans[0].text = String(spans[0].text.drop(while: \.isWhitespace))
        let last = spans.count - 1
        spans[last].text = String(spans[last].text.reversed().drop(while: \.isWhitespace).reversed())
        return SubtitleLine(spans)
    }

    private struct Parser {
        let characters: [Character]
        var index = 0
        var lines: [SubtitleLine] = []
        var spans: [SubtitleSpan] = []
        var buffer = ""
        /// Counted, so a doubled tag needs both closed.
        var bold = 0
        var italic = 0
        /// Inside `<rt>`, ruby text, which is left out.
        var hidden = 0
        var placement = SubtitleCue.Placement.bottom

        init(_ characters: [Character]) {
            self.characters = characters
        }

        mutating func run() {
            while index < characters.count {
                if !markup() {
                    append(String(characters[index]))
                    index += 1
                }
            }
            endLine()
        }

        /// Takes in the markup at `index` and moves past it, or returns `false` for plain text.
        private mutating func markup() -> Bool {
            switch characters[index] {
            case "\n":
                endLine()
                index += 1
                return true
            case "\r":
                index += 1
                return true
            case "<":
                return tag()
            case "{":
                return overrides()
            case "\\":
                return escape()
            case "&":
                return entity()
            default:
                return false
            }
        }

        private mutating func append(_ text: String) {
            guard hidden == 0 else { return }
            buffer += text
        }

        /// Ends the run of text in the current style.
        private mutating func flush() {
            guard !buffer.isEmpty else { return }
            let span = SubtitleSpan(buffer, isBold: bold > 0, isItalic: italic > 0)
            buffer = ""
            if let last = spans.last, last.isBold == span.isBold, last.isItalic == span.isItalic {
                spans[spans.count - 1].text += span.text
            } else {
                spans.append(span)
            }
        }

        private mutating func endLine() {
            flush()
            lines.append(SubtitleLine(spans))
            spans = []
        }

        /// An HTML-like tag: `<` then a letter or digit (after an optional `/`), up to `>` on the
        /// same line. Anything else, such as "a < b", is text.
        private mutating func tag() -> Bool {
            var end = index + 1
            let isClosing = end < characters.count && characters[end] == "/"
            if isClosing {
                end += 1
            }
            guard end < characters.count, characters[end].isLetter || characters[end].isNumber else { return false }
            let nameStart = end
            while end < characters.count, !["<", ">", "\n"].contains(characters[end]) {
                end += 1
            }
            guard end < characters.count, characters[end] == ">" else { return false }
            let name = String(characters[nameStart ..< end].prefix { $0.isLetter || $0.isNumber }).lowercased()
            flush()
            let step = isClosing ? -1 : 1
            switch name {
            case "b": bold = max(bold + step, 0)
            case "i": italic = max(italic + step, 0)
            case "rt": hidden = max(hidden + step, 0)
            default: break
            }
            index = end + 1
            return true
        }

        /// ASS override tags, such as `{\i1}` or `{\an8}`.
        private mutating func overrides() -> Bool {
            guard index + 1 < characters.count, characters[index + 1] == "\\",
                  let end = characters[index...].firstIndex(of: "}")
            else { return false }
            flush()
            let tags = String(characters[(index + 1) ..< end]).split(separator: "\\")
            for tag in tags {
                apply(override: tag.trimmingCharacters(in: .whitespaces).lowercased())
            }
            index = end + 1
            return true
        }

        private mutating func apply(override tag: String) {
            if tag.hasPrefix("an"), let number = Int(tag.dropFirst(2)) {
                placement = (7 ... 9).contains(number) ? .top : .bottom
            } else if tag.hasPrefix("i"), let value = Int(tag.dropFirst()) {
                italic = value == 0 ? 0 : 1
            } else if tag.hasPrefix("b"), let value = Int(tag.dropFirst()) {
                // `\b1`, or a weight, where 700 and up is bold.
                bold = value == 1 || value >= 700 ? 1 : 0
            }
        }

        /// ASS's `\N` and `\n` break the line, and `\h` is a space.
        private mutating func escape() -> Bool {
            guard index + 1 < characters.count else { return false }
            switch characters[index + 1] {
            case "N", "n":
                endLine()
            case "h":
                append("\u{00A0}")
            default:
                return false
            }
            index += 2
            return true
        }

        private static let entities: [String: String] = [
            "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
            "nbsp": "\u{00A0}", "lrm": "\u{200E}", "rlm": "\u{200F}",
        ]

        private mutating func entity() -> Bool {
            let limit = min(index + 10, characters.count)
            guard let end = characters[index ..< limit].firstIndex(of: ";") else { return false }
            let name = String(characters[(index + 1) ..< end])
            let decoded: String? = if name.hasPrefix("#x") || name.hasPrefix("#X") {
                UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String($0) }
            } else if name.hasPrefix("#") {
                UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String($0) }
            } else {
                Self.entities[name.lowercased()]
            }
            guard let decoded else { return false }
            append(decoded)
            index = end + 1
            return true
        }
    }
}
