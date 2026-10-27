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
            default: nil
            }
        }
        return sent
    }

    @Test func `recordings under way come from the recordings, as in Wholphin, so they play`() async throws {
        let sent = registerSchedule(host: "active.test")

        let schedule = try await session(host: "active.test").liveTVSchedule()

        #expect(schedule.active.map(\.id) == ["r1"])
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

    /// One recording under way, and one the server sent without times, which isn't listed.
    private static let recordings = MockServer.Reply.json(#"""
    {"Items":[{"Id":"r1","Name":"Now","Type":"Recording","TimerId":"t1","SeriesTimerId":"s1",
      "ProgramId":"p1","ChannelName":"Anemone One","IsSeries":true,"EpisodeTitle":"Stripes",
      "Status":"InProgress","ImageTags":{"Primary":"art"},
      "StartDate":"2026-10-26T10:00:00.0000000Z","EndDate":"2026-10-26T11:00:00.0000000Z"},
     {"Id":"r2","Name":"No times"}]}
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
