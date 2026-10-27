import Foundation

/// One subtitle: its text and when it shows, from `start` until just before `end`.
public struct SubtitleCue: Hashable, Sendable {
    /// Where on the screen a cue sits. Most sit at the bottom; signs and lyrics are often moved
    /// to the top so they don't cover the dialogue.
    public enum Placement: Hashable, Sendable {
        case bottom
        case top
    }

    public var start: Duration
    public var end: Duration
    /// One entry per line, as the file breaks them.
    public var lines: [SubtitleLine]
    public var placement: Placement

    public init(start: Duration, end: Duration, lines: [SubtitleLine], placement: Placement = .bottom) {
        self.start = start
        self.end = end
        self.lines = lines
        self.placement = placement
    }

    /// The text without its styling, lines joined with newlines.
    public var text: String {
        lines.map(\.text).joined(separator: "\n")
    }
}

/// A line of a cue, in runs of the same style.
public struct SubtitleLine: Hashable, Sendable {
    public var spans: [SubtitleSpan]

    public init(_ spans: [SubtitleSpan]) {
        self.spans = spans
    }

    public var text: String {
        spans.map(\.text).joined()
    }
}

/// Text in one style: the bold and italic that SRT and WebVTT tags ask for.
public struct SubtitleSpan: Hashable, Sendable {
    public var text: String
    public var isBold: Bool
    public var isItalic: Bool

    public init(_ text: String, isBold: Bool = false, isItalic: Bool = false) {
        self.text = text
        self.isBold = isBold
        self.isItalic = isItalic
    }
}
