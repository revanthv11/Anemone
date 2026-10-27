@testable import AnemoneJellyfin
import Foundation
import Testing

/// The DVR schedule and the recording folders, against the fake server.
struct LiveTVScheduleTests: LiveTVServerTesting {
    /// Answers the schedule's three requests, recording each by its path.
    private func registerSchedule(host: String) -> LiveTVRecorder {
        let sent = LiveTVRecorder()
        MockServer.register(host: host) { request in
            let path = request.url?.path() ?? ""
            sent.sent.withLock { $0.append((path, SentRequest(request))) }
            return switch path {
            case "/LiveTv/Recordings": Self.recordings
            case "/LiveTv/Timers": Self.timers
            case "/LiveTv/SeriesTimers": Self.seriesTimers
            case "/LiveTv/Timers/t9": Self.timerOfRecordingWithoutTimes
            default: nil
            }
        }
        return sent
    }

    @Test func `recordings under way come from the recordings, as in Wholphin, so they play`() async throws {
        let sent = registerSchedule(host: "active.test")

        let schedule = try await session(host: "active.test").liveTVSchedule()

        #expect(schedule.active.map(\.id) == ["r1", "r2", "r3"])
        let recording = schedule.active[0].program
        #expect(recording.id == "p1")
        #expect(recording.name == "Now")
        #expect(recording.subtitle == "Stripes")
        #expect(recording.channelName == "Anemone One")
        #expect(recording.timerID == "t1")
        #expect(recording.seriesTimerID == "s1")
        #expect(recording.image == ItemImage(itemID: "r1", kind: .primary, tag: "art"))
        let query = try #require(sent.all.first { $0.key == "/LiveTv/Recordings" }).request.query
        #expect(query["isInProgress"] == "true")
        #expect(query["limit"] == "100")
        #expect(query["userId"] == "u1")
        // Only a recording that came without times asks for its timer.
        #expect(sent.all.filter { $0.key.hasPrefix("/LiveTv/Timers/") }.map(\.key) == ["/LiveTv/Timers/t9"])
    }

    @Test func `a recording under way without times is listed with its timer's, or its own length`() async throws {
        _ = registerSchedule(host: "untimed.test")

        let active = try await session(host: "untimed.test").liveTVSchedule().active

        let fromTimer = try #require(active.first { $0.id == "r2" }).program
        #expect(fromTimer.start == Self.date("2026-10-26T10:30:00Z"))
        #expect(fromTimer.end == Self.date("2026-10-26T11:00:00Z"))
        #expect(fromTimer.channelID == "c9")
        #expect(fromTimer.timerID == "t9")
        let fromLength = try #require(active.first { $0.id == "r3" }).program
        #expect(fromLength.start == Self.date("2026-10-26T10:00:00Z"))
        #expect(fromLength.duration == .seconds(1200))
        // One with neither is left out, and logged.
        #expect(!active.contains { $0.id == "r4" })
    }

    @Test func `scheduled recordings come from the timers, then the series set to record`() async throws {
        let sent = registerSchedule(host: "scheduled.test")

        let schedule = try await session(host: "scheduled.test").liveTVSchedule()

        #expect(schedule.scheduled.map(\.id) == ["t2", "t3"])
        #expect(schedule.scheduled[0].program.seriesTimerID == "s1")
        #expect(schedule.scheduled[0].program.channelName == "Anemone News")
        #expect(schedule.scheduled[1].program.name == "By time")
        #expect(schedule.scheduled[1].program.channelID == "c3")
        #expect(schedule.series == [LiveTVSeriesTimer(
            id: "s1",
            name: "Pattern Patrol",
            channelName: "Anemone One",
            recordsAnyTime: true,
            recordsNewOnly: true,
        )])
        // Only the scheduled timers: what's recording comes from the recordings.
        let timers = sent.all.filter { $0.key == "/LiveTv/Timers" }.map(\.request.query)
        #expect(timers.count == 1)
        #expect(timers.first?["isActive"] == "false")
        #expect(timers.first?["isScheduled"] == "true")
    }

    @Test func `recording folders become libraries`() async throws {
        let sent = register(host: "folders.test", replies: ["GET /LiveTv/Recordings/Folders": .json(#"""
        {"Items":[{"Id":"f1"},{"Id":"f2","Name":"Recorded Shows","CollectionType":"tvshows"},{"Name":"No ID"}]}
        """#)])

        let folders = try await session(host: "folders.test").liveTVRecordingFolders()

        #expect(folders.map(\.id) == ["f1", "f2"])
        #expect(folders.map(\.name) == ["Recordings", "Recorded Shows"])
        #expect(folders.map(\.kind) == [.folders, .folders])
        #expect(sent.request("GET /LiveTv/Recordings/Folders")?.query["userId"] == "u1")
    }

    @Test func `a recording folder lists its top level with the video sort options, as Wholphin does`() async throws {
        _ = register(host: "folder-grid.test", replies: ["GET /LiveTv/Recordings/Folders": .json(#"""
        {"Items":[{"Id":"f2","Name":"Recorded Shows","CollectionType":"tvshows"}]}
        """#)])
        let shows = try #require(try await session(host: "folder-grid.test").liveTVRecordingFolders().first)

        let parameters = LibraryQuery(library: shows).itemsParameters(userID: "u1")

        #expect(parameters.parentID == "f2")
        #expect(parameters.isRecursive == false)
        #expect(parameters.includeItemTypes == nil)
        #expect(shows.sortFields == [
            .name, .premiereDate, .dateCreated, .datePlayed, .communityRating, .criticRating, .officialRating,
            .runtime, .playCount, .random,
        ])
    }

    private static func date(_ text: String) -> Date? {
        try? Date(text, strategy: .iso8601)
    }

    /// One recording under way; one the server sent without times but with its timer; one with
    /// its start and length but no end; and one with nothing to go on, which isn't listed.
    private static let recordings = MockServer.Reply.json(#"""
    {"Items":[{"Id":"r1","Name":"Now","Type":"Recording","TimerId":"t1","SeriesTimerId":"s1",
      "ProgramId":"p1","ChannelName":"Anemone One","IsSeries":true,"EpisodeTitle":"Stripes",
      "Status":"InProgress","ImageTags":{"Primary":"art"},
      "StartDate":"2026-10-26T10:00:00.0000000Z","EndDate":"2026-10-26T11:00:00.0000000Z"},
     {"Id":"r2","Name":"No times","TimerId":"t9"},
     {"Id":"r3","Name":"Own length","StartDate":"2026-10-26T10:00:00.0000000Z","RunTimeTicks":12000000000},
     {"Id":"r4","Name":"Nothing to go on"}]}
    """#)

    private static let timerOfRecordingWithoutTimes = MockServer.Reply.json(#"""
    {"Id":"t9","ChannelId":"c9","Name":"No times","Status":"InProgress",
     "StartDate":"2026-10-26T10:30:00.0000000Z","EndDate":"2026-10-26T11:00:00.0000000Z"}
    """#)

    /// A programme's timer, one set by time alone, and one with nothing to show.
    private static let timers = MockServer.Reply.json(#"""
    {"Items":[{"Id":"t2","SeriesTimerId":"s1","ChannelId":"c2","ChannelName":"Anemone News",
      "ProgramInfo":{"Id":"p2","ChannelId":"c2","Name":"Later",
        "StartDate":"2026-10-26T12:00:00.0000000Z","EndDate":"2026-10-26T13:00:00.0000000Z"}},
     {"Id":"t3","ChannelId":"c3","Name":"By time","StartDate":"2026-10-27T08:00:00.0000000Z",
      "EndDate":"2026-10-27T09:00:00.0000000Z"},
     {"Id":"t4","Name":"Nothing to show"}]}
    """#)

    private static let seriesTimers = MockServer.Reply.json(#"""
    {"Items":[{"Id":"s1","Name":"Pattern Patrol","ChannelName":"Anemone One","RecordAnyChannel":false,
      "RecordAnyTime":true,"RecordNewOnly":true}]}
    """#)
}
