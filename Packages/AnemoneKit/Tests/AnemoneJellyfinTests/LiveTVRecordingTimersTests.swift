@testable import AnemoneJellyfin
import Foundation
import JellyfinAPI
import Testing

/// The timers of recordings under way that came without times: asked for together, a few at a
/// time, rather than one after another.
struct LiveTVRecordingTimersTests: LiveTVServerTesting {
    @Test(.timeLimit(.minutes(1)))
    func `timers are asked for a few at a time, each once`() async {
        // Six timers, one of them for two recordings.
        let dtos = (1 ... 6).map { BaseItemDto(id: "r\($0)", timerID: "t\($0)") }
            + [BaseItemDto(id: "r7", timerID: "t1")]
        let width = LiveTVRecording.timerRequestWidth
        // Holds each request until `width` are under way at once: asked one after another, the
        // first would wait for ever.
        let gate = TimerGate(opensAt: width)

        let recordings = await LiveTVRecording.withTimes(dtos) { id in
            await gate.arrive(id)
            await gate.leave()
            return TimerInfoDto(
                channelID: "c1",
                endDate: Date(timeIntervalSince1970: 3600),
                id: id,
                startDate: Date(timeIntervalSince1970: 0),
            )
        }

        #expect(await gate.asked.sorted() == ["t1", "t2", "t3", "t4", "t5", "t6"])
        #expect(await gate.mostAtOnce == width)
        #expect(recordings.map(\.id) == ["r1", "r2", "r3", "r4", "r5", "r6", "r7"])
        #expect(recordings.allSatisfy { $0.program.duration == .seconds(3600) })
    }

    @Test func `a recording under way as Jellyfin 12.3 sends it keeps the times it came with`() async throws {
        // What the fixture server sent for a recording under way (`GET /LiveTv/Recordings` with
        // `IsInProgress=true`): its timer's times and ID, no length, and no programme or channel ID.
        let sent = register(host: "live-shape.test", replies: [
            "GET /LiveTv/Recordings": .json(#"""
            {"Items":[{"Id":"b4666c47","Name":"Headline Hour","Type":"Recording","Status":"InProgress",
              "ChannelId":null,"ChannelName":"Anemone News","IsSeries":false,"CompletionPercentage":0,
              "StartDate":"2026-10-27T18:00:00.0000000Z","EndDate":"2026-10-27T19:00:00.0000000Z",
              "TimerId":"d37b419a"}],"TotalRecordCount":1}
            """#),
            "GET /LiveTv/Timers": .json(#"{"Items":[]}"#),
            "GET /LiveTv/SeriesTimers": .json(#"{"Items":[]}"#),
        ])

        let schedule = try await session(host: "live-shape.test").liveTVSchedule()

        let program = try #require(schedule.active.first).program
        // Its times came with it, so its timer isn't asked for.
        #expect(!sent.keys.contains { $0.hasPrefix("GET /LiveTv/Timers/") })
        #expect(program.start == (try? Date("2026-10-27T18:00:00Z", strategy: .iso8601)))
        #expect(program.end == (try? Date("2026-10-27T19:00:00Z", strategy: .iso8601)))
        #expect(program.timerID == "d37b419a")
        #expect(program.channelName == "Anemone News")
    }

    @Test func `recordings with times ask for no timers`() async {
        let dto = BaseItemDto(
            channelID: "c1",
            endDate: Date(timeIntervalSince1970: 3600),
            id: "r1",
            startDate: Date(timeIntervalSince1970: 0),
            timerID: "t1",
        )
        let gate = TimerGate(opensAt: 1)

        let recordings = await LiveTVRecording.withTimes([dto]) { id in
            await gate.arrive(id)
            return nil
        }

        #expect(await gate.asked.isEmpty)
        #expect(recordings.map(\.program.timerID) == ["t1"])
    }
}

/// Lets requests through once `opensAt` are under way together, counting how many ever were.
private actor TimerGate {
    let opensAt: Int
    private(set) var asked: [String] = []
    private(set) var mostAtOnce = 0
    private var underWay = 0
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(opensAt: Int) {
        self.opensAt = opensAt
    }

    func arrive(_ id: String) async {
        asked.append(id)
        underWay += 1
        mostAtOnce = max(mostAtOnce, underWay)
        if underWay >= opensAt {
            isOpen = true
            waiting.forEach { $0.resume() }
            waiting = []
        }
        guard !isOpen else { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func leave() {
        underWay -= 1
    }
}
