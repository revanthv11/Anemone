@testable import AnemoneJellyfin
import Foundation
import Synchronization
import Testing

/// Live TV requests against the fake server: channels, the guide, recording and Home's rows. The
/// DVR schedule and recording folders are in `LiveTVScheduleTests`.
struct LiveTVTests: LiveTVServerTesting {
    private static let empty = MockServer.Reply.json(#"{"Items":[]}"#)
    private static let noContent = MockServer.Reply(status: 204, body: "")

    @Test func `channels come in the guide's order with their logo, favourite and programme`() async throws {
        let sent = register(host: "channels.test", replies: ["GET /LiveTv/Channels": .json(#"""
        {"Items":[{"Id":"c1","Name":"Anemone One","ChannelNumber":"1","ImageTags":{"Primary":"logo1"},
          "UserData":{"Key":"c1","IsFavorite":true},
          "CurrentProgram":{"Id":"p1","ChannelId":"c1","Name":"News Hour",
            "StartDate":"2026-10-26T10:00:00.0000000Z","EndDate":"2026-10-26T11:00:00.0000000Z"}},
         {"Id":"c2","Name":"Anemone News","Number":"2"},
         {"Name":"No id"}]}
        """#)])

        let channels = try await session(host: "channels.test").liveTVChannels(includesCurrentProgram: true)

        #expect(channels.map(\.title) == ["1 Anemone One", "2 Anemone News"])
        #expect(channels.map(\.isFavorite) == [true, false])
        #expect(channels[0].image == ItemImage(itemID: "c1", kind: .primary, tag: "logo1"))
        #expect(channels[0].currentProgram?.name == "News Hour")
        #expect(channels[1].image == nil)
        let query = try #require(sent.request("GET /LiveTv/Channels")).query
        #expect(query["userId"] == "u1")
        #expect(query["startIndex"] == "0")
        #expect(query["enableFavoriteSorting"] == "true")
        #expect(query["addCurrentProgram"] == "true")
        #expect(query["sortBy"] == nil)
    }

    @Test func `recently watched channels come first when asked`() async throws {
        let sent = register(host: "recent.test", replies: ["GET /LiveTv/Channels": Self.empty])

        _ = try await session(host: "recent.test")
            .liveTVChannels(order: LiveTVChannelOrder(favoritesFirst: false, recentlyWatchedFirst: true))

        let query = try #require(sent.request("GET /LiveTv/Channels")).query
        #expect(query["sortBy"] == "DatePlayed")
        #expect(query["sortOrder"] == "Descending")
        #expect(query["enableFavoriteSorting"] == "false")
        #expect(query["addCurrentProgram"] == "false")
    }

    @Test func `the guide asks for the listings overlapping it, as Wholphin does`() async throws {
        let sent = register(host: "guide.test", replies: ["POST /LiveTv/Programs": .json(#"""
        {"Items":[
          {"Id":"p0","ChannelId":"c1","Name":"Over","StartDate":"2026-10-26T09:00:00.0000000Z",
           "EndDate":"2026-10-26T10:30:00.0000000Z"},
          {"Id":"p1","ChannelId":"c1","Name":"Pattern Patrol: The  Spiral","SeriesName":"Pattern\n Patrol",
           "EpisodeTitle":"The\nSpiral","IsSeries":true,"ParentIndexNumber":1,"IndexNumber":3,"IsKids":true,
           "IsRepeat":true,"TimerId":"t1","SeriesTimerId":"","OfficialRating":"TV-Y",
           "StartDate":"2026-10-26T10:00:00.0000000Z","EndDate":"2026-10-26T11:00:00.0000000Z"},
          {"Id":"p2","ChannelId":"c1","Name":"Film","EpisodeTitle":"Not a series","IndexNumber":4,"IsMovie":true,
           "StartDate":"2026-10-26T11:00:00.0000000Z","EndDate":"2026-10-26T13:00:00.0000000Z"},
          {"Id":"p3","Name":"No channel","StartDate":"2026-10-26T11:00:00.0000000Z",
           "EndDate":"2026-10-26T12:00:00.0000000Z"}
        ]}
        """#)])
        let guide = try LiveTVGuide(now: #require(ISO8601DateFormatter().date(from: "2026-10-26T10:40:00Z")))

        let programs = try await session(host: "guide.test").liveTVPrograms(channelIDs: ["c1", "c2"], in: guide)

        #expect(programs.map(\.id) == ["p1", "p2"])
        let episode = programs[0]
        #expect(episode.name == "Pattern Patrol")
        #expect(episode.episodeTitle == "The Spiral")
        #expect(episode.subtitle == "S1:E3 - The Spiral")
        #expect(episode.category == .kids)
        #expect(episode.isRepeat)
        #expect(episode.timerID == "t1")
        #expect(episode.seriesTimerID == nil)
        #expect(episode.officialRating == "TV-Y")
        #expect(programs[1].episodeTitle == nil)
        #expect(programs[1].episodeLabel == nil)
        #expect(programs[1].category == .movie)

        let body = try #require(sent.request("POST /LiveTv/Programs")).json
        #expect(body["ChannelIds"] as? [String] == ["c1", "c2"])
        #expect(body["UserId"] as? String == "u1")
        #expect(body["SortBy"] as? [String] == ["StartDate"])
        #expect(body["Fields"] as? [String] == ["Overview"])
        #expect(Self.date(body["MinEndDate"]) == guide.start.addingTimeInterval(60))
        #expect(Self.date(body["MaxStartDate"]) == guide.end.addingTimeInterval(-60))
    }

    @Test func `a programme is loaded with its recording state`() async throws {
        let sent = register(host: "program.test", replies: ["GET /LiveTv/Programs/p1": .json(#"""
        {"Id":"p1","ChannelId":"c1","ChannelName":"Anemone One","Name":"Pattern Patrol","IsSeries":true,
         "SeriesTimerId":"s1","StartDate":"2026-10-26T10:00:00.0000000Z","EndDate":"2026-10-26T10:30:00.0000000Z"}
        """#)])

        let program = try await session(host: "program.test").liveTVProgram(id: "p1")

        #expect(program.channelName == "Anemone One")
        #expect(program.seriesTimerID == "s1")
        #expect(program.timerID == nil)
        #expect(program.duration == .seconds(1800))
        #expect(sent.request("GET /LiveTv/Programs/p1")?.query["userId"] == "u1")
    }

    @Test func `recording a programme copies the server's default timer`() async throws {
        let sent = register(host: "record.test", replies: [
            "GET /LiveTv/Timers/Defaults": Self.defaultTimer,
            "POST /LiveTv/Timers": Self.noContent,
        ])

        try await session(host: "record.test").record(programID: "p1", series: false)

        #expect(sent.keys == ["GET /LiveTv/Timers/Defaults", "POST /LiveTv/Timers"])
        #expect(sent.request("GET /LiveTv/Timers/Defaults")?.query["programId"] == "p1")
        let body = try #require(sent.request("POST /LiveTv/Timers")).json
        #expect(body["ProgramId"] as? String == "p1")
        #expect(body["ChannelId"] as? String == "c1")
        #expect(body["PrePaddingSeconds"] as? Int == 60)
        #expect(body["PostPaddingSeconds"] as? Int == 120)
        #expect(body["KeepUntil"] as? String == "UntilDeleted")
        #expect(body["RecordAnyChannel"] == nil)
    }

    @Test func `recording a series sends the default series timer as it is`() async throws {
        let sent = register(host: "series.test", replies: [
            "GET /LiveTv/Timers/Defaults": Self.defaultTimer,
            "POST /LiveTv/SeriesTimers": Self.noContent,
        ])

        try await session(host: "series.test").record(programID: "p1", series: true)

        let body = try #require(sent.request("POST /LiveTv/SeriesTimers")).json
        #expect(body["ProgramId"] as? String == "p1")
        #expect(body["RecordAnyChannel"] as? Bool == false)
        #expect(body["RecordNewOnly"] as? Bool == true)
    }

    @Test func `cancelling deletes the timer or the series timer`() async throws {
        let sent = register(host: "cancel.test", replies: [
            "DELETE /LiveTv/Timers/t1": Self.noContent,
            "DELETE /LiveTv/SeriesTimers/s1": Self.noContent,
        ])
        let session = try session(host: "cancel.test")

        try await session.cancelRecording(timerID: "t1", series: false)
        try await session.cancelRecording(timerID: "s1", series: true)

        #expect(sent.keys == ["DELETE /LiveTv/Timers/t1", "DELETE /LiveTv/SeriesTimers/s1"])
    }

    @Test func `closing a live stream names it`() async throws {
        let sent = register(host: "close.test", replies: ["POST /LiveStreams/Close": Self.noContent])

        try await session(host: "close.test").closeLiveStream(id: "ls1")

        #expect(sent.request("POST /LiveStreams/Close")?.query["liveStreamId"] == "ls1")
    }

    @Test func `home's Live TV rows ask for what Wholphin's rows show`() async throws {
        let sent = register(host: "home.test", replies: [
            "GET /LiveTv/Recordings": .json(#"{"Items":[{"Id":"r1","Name":"Recording","Type":"Recording"}]}"#),
            "POST /LiveTv/Programs": .json(#"{"Items":[{"Id":"p1","Name":"On now","Type":"Program"}]}"#),
            "GET /LiveTv/Channels": .json(#"{"Items":[{"Id":"c1","Name":"Anemone One","Type":"TvChannel"}]}"#),
        ])
        let rows = try session(host: "home.test").liveTVHomeRows

        let recordings = try await rows.recordingsInProgress(limit: 5)
        #expect(recordings.map(\.id) == ["r1"])
        // A recording plays from its page, so it keeps its own kind rather than falling to `other`.
        #expect(recordings.map(\.kind) == [.recording])
        let onNow = try await rows.programsOnNow(limit: 6)
        #expect(onNow.map(\.id) == ["p1"])
        #expect(onNow.map(\.kind) == [.tvProgram])
        let channels = try await rows.channels(limit: 7)
        #expect(channels.map(\.id) == ["c1"])
        #expect(channels.map(\.kind) == [.tvChannel])

        let recordingsQuery = try #require(sent.request("GET /LiveTv/Recordings")).query
        #expect(recordingsQuery["isInProgress"] == "true")
        #expect(recordingsQuery["limit"] == "5")
        let programs = try #require(sent.request("POST /LiveTv/Programs")).json
        #expect(programs["IsAiring"] as? Bool == true)
        #expect(programs["Limit"] as? Int == 6)
        #expect(programs["Fields"] as? [String] == ["Overview", "CanDelete", "ChannelInfo"])
        #expect(sent.request("GET /LiveTv/Channels")?.query["limit"] == "7")
    }

    private static let defaultTimer = MockServer.Reply.json(#"""
    {"Id":"","ProgramId":"p1","ChannelId":"c1","Name":"Pattern Patrol","PrePaddingSeconds":60,
     "PostPaddingSeconds":120,"KeepUntil":"UntilDeleted","RecordAnyChannel":false,"RecordAnyTime":false,
     "RecordNewOnly":true,"StartDate":"2026-10-26T12:00:00.0000000Z","EndDate":"2026-10-26T12:30:00.0000000Z"}
    """#)

    /// A date from a request body, however many fractional digits the SDK wrote.
    private static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

/// A session on the fake server, and a way to answer its requests, for the Live TV tests.
protocol LiveTVServerTesting {}

extension LiveTVServerTesting {
    func session(host: String) throws -> JellyfinSession {
        try JellyfinSession(
            serverURL: #require(URL(string: "https://\(host)")),
            userID: "u1",
            accessToken: "tok",
            identity: ClientIdentity(deviceName: "Test TV", deviceID: "device-1", appVersion: "0.1.0"),
            sessionConfiguration: { MockServer.sessionConfiguration() },
        )
    }

    /// Answers "METHOD /path" with its reply, recording every request in order.
    func register(host: String, replies: [String: MockServer.Reply]) -> LiveTVRecorder {
        let recorder = LiveTVRecorder()
        MockServer.register(host: host) { request in
            let key = "\(request.httpMethod ?? "GET") \(request.url?.path() ?? "")"
            guard let reply = replies[key] else { return nil }
            recorder.sent.withLock { $0.append((key, SentRequest(request))) }
            return reply
        }
        return recorder
    }
}

/// Every request a test's fake server answered, in order, by "METHOD /path".
final class LiveTVRecorder: Sendable {
    let sent = Mutex<[(key: String, request: SentRequest)]>([])

    var all: [(key: String, request: SentRequest)] {
        sent.withLock(\.self)
    }

    var keys: [String] {
        all.map(\.key)
    }

    func request(_ key: String) -> SentRequest? {
        all.last { $0.key == key }?.request
    }
}
