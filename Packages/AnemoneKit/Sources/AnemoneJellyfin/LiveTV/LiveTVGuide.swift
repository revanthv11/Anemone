import Foundation

/// The guide's span and rows, ported from Wholphin's `LiveTvViewModel`: 48 hours from now,
/// rounded down to the half hour, with each channel's programmes laid end to end and the gaps
/// filled in.
///
/// Times are kept as instants rather than Wholphin's local date-times, so a programme across a
/// daylight-saving change keeps its real length without Wholphin's special case.
public struct LiveTVGuide: Hashable, Sendable {
    /// How far ahead the guide reaches, Wholphin's `MAX_HOURS`.
    public static let hours = 48
    static let hour: TimeInterval = 3600
    static let halfHour: TimeInterval = 1800

    public let start: Date

    /// - Parameter now: rounded down to the half hour in `calendar`'s time zone, as Wholphin's
    ///   `roundDownToHalfHour`.
    public init(now: Date = .now, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.minute, .second, .nanosecond], from: now)
        let past = Double((parts.minute ?? 0) % 30) * 60 + Double(parts.second ?? 0)
            + Double(parts.nanosecond ?? 0) / 1_000_000_000
        start = now.addingTimeInterval(-past)
    }

    public var end: Date {
        start.addingTimeInterval(Double(Self.hours) * Self.hour)
    }

    /// A channel's row from the guide's start to its end: its programmes in order, with every
    /// gap filled by placeholders of an hour at most, as Wholphin's `fetchPrograms` does. A
    /// channel with no listings gets one for each hour. Placeholders end on the guide's hours,
    /// so they line up from row to row.
    public func row(channelID: String, programs: [LiveTVProgram]) -> [LiveTVProgram] {
        var row: [LiveTVProgram] = []
        var cursor = start
        for program in programs.sorted(by: { $0.start < $1.start }) where program.end > cursor {
            if program.start > cursor {
                row += placeholders(channelID: channelID, from: cursor, to: min(program.start, end))
            }
            guard program.start < end else { break }
            row.append(program)
            cursor = program.end
        }
        if cursor < end {
            row += placeholders(channelID: channelID, from: cursor, to: end)
        }
        return row
    }

    /// The part of `row` inside `window`, each cell cut to the window and to the cell before it,
    /// so overlapping listings don't overlap on screen.
    public func cells(in row: [LiveTVProgram], window: DateInterval) -> [LiveTVGuideCell] {
        var cells: [LiveTVGuideCell] = []
        var cursor = window.start
        for program in row where program.end > cursor && program.start < window.end {
            let cellStart = max(program.start, cursor)
            let cellEnd = min(program.end, window.end)
            guard cellEnd > cellStart else { continue }
            cells.append(LiveTVGuideCell(program: program, start: cellStart, end: cellEnd))
            cursor = cellEnd
        }
        return cells
    }

    /// The window of `length` starting at `start`, kept inside the guide.
    public func window(from start: Date, length: TimeInterval) -> DateInterval {
        let latest = max(self.start, end.addingTimeInterval(-length))
        let clamped = min(max(start, self.start), latest)
        return DateInterval(start: clamped, duration: min(length, end.timeIntervalSince(self.start)))
    }

    /// Where the window goes when focus moves right past its end onto `program`: the programme's
    /// start half an hour in from the left, so a little of what came before still shows.
    public func window(movingForwardTo program: LiveTVProgram, length: TimeInterval) -> DateInterval {
        window(from: halfHour(before: program.start).addingTimeInterval(-Self.halfHour), length: length)
    }

    /// Where the window goes when focus moves left past its start onto `program`: the programme's
    /// end half an hour in from the right.
    public func window(movingBackTo program: LiveTVProgram, length: TimeInterval) -> DateInterval {
        let rightEdge = halfHour(after: program.end).addingTimeInterval(Self.halfHour)
        return window(from: rightEdge.addingTimeInterval(-length), length: length)
    }

    /// The programme focus moves to from the window's last cell in `row`: the first that starts
    /// at or after the window's end. `nil` when the last one runs to the guide's end.
    public func program(after window: DateInterval, in row: [LiveTVProgram]) -> LiveTVProgram? {
        row.first { $0.start >= window.end }
    }

    /// The programme focus moves to from the window's first cell in `row`: the last that ends at
    /// or before the window's start.
    public func program(before window: DateInterval, in row: [LiveTVProgram]) -> LiveTVProgram? {
        row.last { $0.end <= window.start }
    }

    /// The half hours from the guide's start inside `window`, for the times along its top.
    public func halfHours(in window: DateInterval) -> [Date] {
        var marks: [Date] = []
        var mark = halfHour(after: window.start)
        while mark < window.end {
            marks.append(mark)
            mark = mark.addingTimeInterval(Self.halfHour)
        }
        return marks
    }

    /// The guide's half hour at or before `date`.
    func halfHour(before date: Date) -> Date {
        let steps = (date.timeIntervalSince(start) / Self.halfHour).rounded(.down)
        return start.addingTimeInterval(steps * Self.halfHour)
    }

    /// The guide's half hour at or after `date`.
    func halfHour(after date: Date) -> Date {
        let steps = (date.timeIntervalSince(start) / Self.halfHour).rounded(.up)
        return start.addingTimeInterval(steps * Self.halfHour)
    }

    private func placeholders(channelID: String, from first: Date, to last: Date) -> [LiveTVProgram] {
        var placeholders: [LiveTVProgram] = []
        var cursor = first
        while cursor < last {
            let hours = (cursor.timeIntervalSince(start) / Self.hour).rounded(.down) + 1
            let next = min(start.addingTimeInterval(hours * Self.hour), last)
            placeholders.append(LiveTVProgram(
                id: "placeholder-\(channelID)-\(Int(cursor.timeIntervalSince1970))",
                channelID: channelID,
                name: "No data",
                start: cursor,
                end: next,
                isPlaceholder: true,
            ))
            cursor = next
        }
        return placeholders
    }
}

/// A programme as the guide draws it: cut to the window, and to the programme before it.
public struct LiveTVGuideCell: Hashable, Identifiable, Sendable {
    public let program: LiveTVProgram
    public let start: Date
    public let end: Date

    public var id: LiveTVProgram.ID {
        program.id
    }

    /// Whether the programme began before the cell, which Wholphin marks with a caret.
    public var continuesBefore: Bool {
        program.start < start
    }

    public var length: TimeInterval {
        end.timeIntervalSince(start)
    }
}
