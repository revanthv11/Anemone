import AnemoneJellyfin
import Foundation

/// Reads SubRip (`.srt`) files: numbered cues, each a timing line such as
/// `00:01:02,500 --> 00:01:04,000` and its text, separated by blank lines.
///
/// It forgives what real files get wrong: a missing number or blank line, a full stop for the
/// comma, hours left out, Windows or old Mac line endings, and a byte-order mark.
public enum SubRip {
    public static func cues(in text: String) -> [SubtitleCue] {
        let lines = SubtitleText.lines(of: text)
        var cues: [SubtitleCue] = []
        var index = 0
        while index < lines.count {
            guard let timing = SubtitleText.timing(lines[index]) else {
                index += 1
                continue
            }
            index += 1
            var text: [String] = []
            while index < lines.count, !lines[index].allSatisfy(\.isWhitespace), !startsCue(at: index, in: lines) {
                text.append(lines[index])
                index += 1
            }
            if let cue = SubtitleText.cue(timing, text: text) {
                cues.append(cue)
            }
        }
        return cues
    }

    /// A timing line, or a cue number right before one: the next cue, in a file that left out the
    /// blank line.
    private static func startsCue(at index: Int, in lines: [String]) -> Bool {
        if SubtitleText.timing(lines[index]) != nil {
            return true
        }
        let isNumber = !lines[index].isEmpty && lines[index].trimmingCharacters(in: .whitespaces).allSatisfy(\.isNumber)
        return isNumber && index + 1 < lines.count && SubtitleText.timing(lines[index + 1]) != nil
    }
}

/// Reads WebVTT files: a `WEBVTT` header, then blocks separated by blank lines. A cue block has
/// an optional identifier, a timing line such as `01:02.500 --> 01:04.000 line:0` and its text;
/// `NOTE`, `STYLE` and `REGION` blocks are skipped.
///
/// The whole file is read as one timeline, as Jellyfin sends it for a subtitle on its own; HLS
/// segments' `X-TIMESTAMP-MAP` isn't read. A cue whose `line` setting puts it in the top half of
/// the picture shows at the top.
public enum WebVTT {
    public static func cues(in text: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        for block in blocks(of: SubtitleText.lines(of: text)) {
            guard let first = block.first,
                  !["WEBVTT", "NOTE", "STYLE", "REGION"].contains(where: { first.hasPrefix($0) }),
                  let timingIndex = block.prefix(2).firstIndex(where: { $0.contains("-->") }),
                  let timing = SubtitleText.timing(block[timingIndex]),
                  var cue = SubtitleText.cue(timing, text: Array(block[(timingIndex + 1)...]))
            else { continue }
            if isNearTop(settings: block[timingIndex]) {
                cue.placement = .top
            }
            cues.append(cue)
        }
        return cues
    }

    private static func blocks(of lines: [String]) -> [[String]] {
        var blocks: [[String]] = []
        var block: [String] = []
        for line in lines {
            if line.allSatisfy(\.isWhitespace) {
                if !block.isEmpty {
                    blocks.append(block)
                }
                block = []
            } else {
                block.append(line)
            }
        }
        if !block.isEmpty {
            blocks.append(block)
        }
        return blocks
    }

    /// The `line` setting: a percentage below 50, or a line number counted from the top (0 and
    /// up; negative ones count from the bottom).
    private static func isNearTop(settings timingLine: String) -> Bool {
        guard let setting = timingLine.split(separator: " ").first(where: { $0.hasPrefix("line:") }) else {
            return false
        }
        let value = setting.dropFirst("line:".count).prefix { $0 != "," }
        if value.hasSuffix("%") {
            return Double(value.dropLast()).map { $0 < 50 } ?? false
        }
        return Int(value).map { $0 >= 0 } ?? false
    }
}

/// Reads a subtitle file in the format it says it's in, or WebVTT when it starts like one.
public extension SubtitleTimeline {
    init(parsing text: String, format: SubtitleFile.Format) {
        let isWebVTT = format == .vtt || SubtitleText.lines(of: text).first?.hasPrefix("WEBVTT") == true
        self.init(isWebVTT ? WebVTT.cues(in: text) : SubRip.cues(in: text))
    }
}

/// What SRT and WebVTT have in common.
enum SubtitleText {
    struct Timing: Equatable {
        var start: Duration
        var end: Duration
    }

    /// The file's lines, whatever its line endings, without a byte-order mark.
    static func lines(of text: String) -> [String] {
        var text = text
        if text.hasPrefix("\u{FEFF}") {
            text.removeFirst()
        }
        return text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    /// `start --> end`, with anything after the end (SRT coordinates, WebVTT settings) ignored.
    static func timing(_ line: String) -> Timing? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count == 2,
              let start = timestamp(parts[0].trimmingCharacters(in: .whitespaces)),
              let endText = parts[1].split(separator: " ", omittingEmptySubsequences: true).first,
              let end = timestamp(String(endText))
        else { return nil }
        return Timing(start: start, end: end)
    }

    /// `hh:mm:ss,ttt`, `hh:mm:ss.ttt` or `mm:ss.ttt`, with one to three digits of fraction (or
    /// none).
    static func timestamp(_ text: String) -> Duration? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard (2 ... 3).contains(parts.count), let last = parts.last else { return nil }
        let seconds = last.split(whereSeparator: { $0 == "," || $0 == "." })
        guard (1 ... 2).contains(seconds.count),
              let whole = Int(seconds[0]),
              let minutes = Int(parts[parts.count - 2]),
              let hours = parts.count == 3 ? Int(parts[0]) : 0,
              [whole, minutes, hours].allSatisfy({ $0 >= 0 })
        else { return nil }
        var milliseconds = 0
        if seconds.count == 2 {
            let fraction = seconds[1].prefix(3)
            guard !fraction.isEmpty, let value = Int(fraction), fraction.allSatisfy(\.isNumber) else { return nil }
            milliseconds = value * [100, 10, 1][fraction.count - 1]
        }
        return .seconds(hours * 3600 + minutes * 60 + whole) + .milliseconds(milliseconds)
    }

    /// A cue with `text`'s lines, or `nil` if it ends before it starts or has nothing to show.
    static func cue(_ timing: Timing, text: [String]) -> SubtitleCue? {
        guard timing.end > timing.start else { return nil }
        let parsed = SubtitleMarkup.parse(text.joined(separator: "\n"))
        guard !parsed.lines.isEmpty else { return nil }
        return SubtitleCue(start: timing.start, end: timing.end, lines: parsed.lines, placement: parsed.placement)
    }
}
