@testable import AnemoneJellyfin
import Foundation
import Testing

/// The guide's span, rows and window, as Wholphin's `LiveTvViewModel` lays them out.
struct LiveTVGuideTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    /// 26 October 2026 at `time` ("HH:mm"), UTC; a day later with `day: 27`.
    private static func date(_ time: String, day: Int = 26) -> Date {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        let components = DateComponents(year: 2026, month: 10, day: day, hour: parts[0], minute: parts[1])
        return calendar.date(from: components) ?? .distantPast
    }

    private static let guide = LiveTVGuide(now: date("10:47"), calendar: calendar)

    private static func program(_ id: String, _ start: String, _ end: String) -> LiveTVProgram {
        LiveTVProgram(id: id, channelID: "c1", name: id, start: date(start), end: date(end))
    }

    private static func window(_ start: String, hours: Double) -> DateInterval {
        DateInterval(start: date(start), duration: hours * 3600)
    }

    @Test func `the guide starts at the half hour before now and runs for 48 hours`() {
        let calendar = Self.calendar
        #expect(LiveTVGuide(now: Self.date("10:47").addingTimeInterval(12.5), calendar: calendar).start
            == Self.date("10:30"))
        #expect(LiveTVGuide(now: Self.date("10:30"), calendar: calendar).start == Self.date("10:30"))
        #expect(LiveTVGuide(now: Self.date("11:05"), calendar: calendar).start == Self.date("11:00"))
        #expect(Self.guide.end == Self.date("10:30", day: 28))
    }

    @Test func `gaps are filled with placeholders that end on the guide's hours`() {
        let row = Self.guide.row(channelID: "c1", programs: [
            Self.program("C", "12:15", "13:00"),
            Self.program("A", "10:00", "11:00"),
            Self.program("B", "11:30", "12:15"),
            Self.program("over", "08:00", "09:00"),
        ])

        #expect(row.prefix(5).map(\.name) == ["A", "No data", "B", "C", "No data"])
        #expect(row[1].start == Self.date("11:00"))
        #expect(row[1].end == Self.date("11:30"))
        #expect(row[1].isPlaceholder)
        #expect(row[4].start == Self.date("13:00"))
        #expect(row[4].end == Self.date("13:30"))
        #expect(row[5].start == Self.date("13:30"))
        #expect(row[5].end == Self.date("14:30"))
        #expect(row.last?.end == Self.guide.end)
        // After C, half an hour to the guide's next hour, then an hour at a time.
        #expect(row.count == 4 + 1 + 45)
        #expect(Set(row.map(\.id)).count == row.count)
    }

    @Test func `a channel without listings gets an hour of no data at a time`() {
        let row = Self.guide.row(channelID: "c9", programs: [])

        #expect(row.count == 48)
        #expect(row.allSatisfy { $0.isPlaceholder && $0.channelID == "c9" && $0.duration == .seconds(3600) })
        #expect(row.first?.start == Self.guide.start)
    }

    @Test func `a gap longer than an hour gets several placeholders`() {
        let row = Self.guide.row(channelID: "c1", programs: [Self.program("Late", "13:00", "14:00")])

        #expect(row.prefix(4).map(\.start) == [
            Self.date("10:30"),
            Self.date("11:30"),
            Self.date("12:30"),
            Self.date("13:00"),
        ])
        #expect(row[2].end == Self.date("13:00"))
    }

    @Test func `cells are cut to the window and don't overlap`() {
        let row = Self.guide.row(channelID: "c1", programs: [
            Self.program("A", "10:00", "11:15"),
            Self.program("B", "11:00", "12:00"),
            Self.program("C", "12:00", "14:00"),
        ])

        let cells = Self.guide.cells(in: row, window: Self.window("10:30", hours: 2.5))

        #expect(cells.map(\.program.name) == ["A", "B", "C"])
        #expect(cells.map(\.start) == [Self.date("10:30"), Self.date("11:15"), Self.date("12:00")])
        #expect(cells.map(\.end) == [Self.date("11:15"), Self.date("12:00"), Self.date("13:00")])
        #expect(cells.map(\.continuesBefore) == [true, true, false])
    }

    @Test func `the window stays inside the guide`() {
        let guide = Self.guide

        #expect(guide.window(from: Self.date("09:00"), length: 9000).start == guide.start)
        #expect(guide.window(from: Self.date("10:00", day: 28), length: 9000).end == guide.end)
        #expect(guide.window(from: Self.date("12:00"), length: 9000) == Self.window("12:00", hours: 2.5))
    }

    @Test func `moving right past the window shows the next programme half an hour in`() throws {
        let guide = Self.guide
        let row = guide.row(channelID: "c1", programs: [
            Self.program("Long", "10:00", "13:10"),
            Self.program("Next", "13:10", "14:00"),
        ])
        let window = Self.window("10:30", hours: 2.5)

        let next = try #require(guide.program(after: window, in: row))
        #expect(next.name == "Next")
        #expect(guide.window(movingForwardTo: next, length: 9000).start == Self.date("12:30"))
    }

    @Test func `moving left past the window shows the earlier programme's end half an hour in`() throws {
        let guide = Self.guide
        let row = guide.row(channelID: "c1", programs: [
            Self.program("Early", "11:00", "12:10"),
            Self.program("Later", "12:10", "18:00"),
        ])
        let window = Self.window("13:00", hours: 2.5)

        let previous = try #require(guide.program(before: window, in: row))
        #expect(previous.name == "Early")
        // 12:10 rounds up to 12:30; half an hour on, the window ends at 13:00.
        #expect(guide.window(movingBackTo: previous, length: 9000) == Self.window("10:30", hours: 2.5))
        #expect(guide.program(before: Self.window("10:30", hours: 2.5), in: row) == nil)
    }

    @Test func `the last programme leaves nothing to move right to`() {
        let guide = Self.guide
        let row = guide.row(channelID: "c1", programs: [Self.program("Marathon", "10:00", "12:00")])
            .filter { !$0.isPlaceholder }

        #expect(guide.program(after: Self.window("10:30", hours: 2.5), in: row) == nil)
    }

    @Test func `times along the top are every half hour in the window`() {
        let marks = Self.guide.halfHours(in: DateInterval(start: Self.date("11:10"), duration: 5400))

        #expect(marks == [Self.date("11:30"), Self.date("12:00"), Self.date("12:30")])
    }

    @Test func `the schedule lists scheduled recordings by day`() {
        let early = LiveTVTimer(id: "t1", program: Self.program("Early", "23:00", "23:30"))
        let late = LiveTVTimer(id: "t2", program: Self.program("Late", "09:00", "10:00"))
        let next = LiveTVTimer(id: "t3", program: LiveTVProgram(
            id: "p3",
            channelID: "c1",
            name: "Tomorrow",
            start: Self.date("08:00", day: 27),
            end: Self.date("09:00", day: 27),
        ))
        let schedule = LiveTVSchedule(scheduled: [next, early, late])

        let days = schedule.scheduledByDay(calendar: Self.calendar)

        #expect(days.map(\.day) == [Self.date("00:00"), Self.date("00:00", day: 27)])
        #expect(days.map { $0.timers.map(\.id) } == [["t2", "t1"], ["t3"]])
    }
}
