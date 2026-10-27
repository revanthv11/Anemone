@testable import AnemoneJellyfin
import Foundation
import Testing

/// Programmes the server says end before they start: no length, no cell in the guide, and times
/// that show rather than trap, in the programme's details and the schedule's rows.
struct LiveTVProgramTimesTests: LiveTVServerTesting {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    /// 26 October 2026 at `hour`:`minute`, UTC.
    private static func date(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: hour, minute: minute)) ?? .distantPast
    }

    @Test func `a programme ending before it starts has no length`() {
        let program = LiveTVProgram(
            id: "p1",
            channelID: "c1",
            name: "Backwards",
            start: Self.date(11),
            end: Self.date(10),
        )

        #expect(program.end == program.start)
        #expect(program.duration == .zero)
        #expect(!program.isAiring(at: Self.date(11)))
    }

    @Test func `the guide leaves a programme without length out of its row, as out of its cells`() {
        let guide = LiveTVGuide(now: Self.date(10, 47), calendar: Self.calendar)
        let backwards = LiveTVProgram(
            id: "p1",
            channelID: "c1",
            name: "Backwards",
            start: Self.date(11),
            end: Self.date(10),
        )
        let next = LiveTVProgram(id: "p2", channelID: "c1", name: "Next", start: Self.date(11), end: Self.date(12))

        let row = guide.row(channelID: "c1", programs: [backwards, next])
        let window = DateInterval(start: guide.start, duration: 2.5 * 3600)

        #expect(!row.contains { $0.id == "p1" })
        #expect(row.contains { $0.id == "p2" })
        #expect(!guide.cells(in: row, window: window).contains { $0.program.id == "p1" })
        #expect(guide.program(after: DateInterval(start: guide.start, end: Self.date(11)), in: row)?.id == "p2")
    }

    @Test func `times show for a programme whose end was moved before its start`() {
        var program = LiveTVProgram(id: "p1", channelID: "c1", name: "Moved", start: Self.date(11), end: Self.date(12))
        let zeroLength = LiveTVProgram(
            id: "p2",
            channelID: "c1",
            name: "Zero",
            start: Self.date(11),
            end: Self.date(11),
        )
        program.end = Self.date(10, 30)

        let times = program.timeRange(now: Self.date(9), calendar: Self.calendar)

        #expect(times == zeroLength.timeRange(now: Self.date(9), calendar: Self.calendar))
        #expect(!times.isEmpty)
    }

    @Test func `the weekday shows for a programme on another day`() {
        let program = LiveTVProgram(id: "p1", channelID: "c1", name: "Later", start: Self.date(11), end: Self.date(12))
        let today = program.timeRange(now: Self.date(9), calendar: Self.calendar)
        let dayBefore = program.timeRange(now: Self.date(9).addingTimeInterval(-86400), calendar: Self.calendar)

        #expect(dayBefore.hasSuffix(today))
        #expect(dayBefore.count > today.count)
    }

    @Test func `the server's backwards programme and timer load with no length`() async throws {
        _ = register(host: "backwards.test", replies: [
            "GET /LiveTv/Programs/p1": .json(#"""
            {"Id":"p1","ChannelId":"c1","Name":"Backwards",
             "StartDate":"2026-10-26T11:00:00.0000000Z","EndDate":"2026-10-26T10:00:00.0000000Z"}
            """#),
            "GET /LiveTv/Recordings": .json(#"{"Items":[]}"#),
            "GET /LiveTv/Timers": .json(#"""
            {"Items":[{"Id":"t1","ChannelId":"c1","ProgramInfo":{"Id":"p1","ChannelId":"c1","Name":"Backwards",
              "StartDate":"2026-10-26T11:00:00.0000000Z","EndDate":"2026-10-26T10:00:00.0000000Z"}},
             {"Id":"t2","ChannelId":"c1","Name":"By time","StartDate":"2026-10-26T12:00:00.0000000Z",
              "EndDate":"2026-10-26T11:30:00.0000000Z"}]}
            """#),
            "GET /LiveTv/SeriesTimers": .json(#"{"Items":[]}"#),
        ])
        let session = try session(host: "backwards.test")

        let program = try await session.liveTVProgram(id: "p1")
        let schedule = try await session.liveTVSchedule()

        #expect(program.end == program.start)
        #expect(schedule.scheduled.map(\.id) == ["t1", "t2"])
        #expect(schedule.scheduled.allSatisfy { $0.program.duration == .zero })
        #expect(schedule.scheduled.allSatisfy { !$0.program.timeRange(calendar: Self.calendar).isEmpty })
    }
}
