import Foundation

/// A license's full text, cut into pieces a TV can scroll through: the remote moves focus from
/// one piece to the next, so no piece may be taller than the screen.
public enum LicenseText {
    /// The paragraphs of `text`, split at blank lines, with any paragraph longer than `maxLines`
    /// cut into runs of `maxLines` lines. Line breaks inside a paragraph are kept, since license
    /// files indent their lists and headings by hand.
    public static func paragraphs(_ text: String, maxLines: Int = 12) -> [String] {
        precondition(maxLines > 0)
        var paragraphs: [String] = []
        var lines: [String] = []

        func flush() {
            if !lines.isEmpty {
                paragraphs.append(lines.joined(separator: "\n"))
                lines = []
            }
        }

        for line in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flush()
            } else {
                lines.append(line.replacingOccurrences(of: "\t", with: "    "))
                if lines.count == maxLines {
                    flush()
                }
            }
        }
        flush()
        return paragraphs
    }
}
