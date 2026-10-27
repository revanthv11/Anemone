import AnemoneJellyfin
import Foundation
import Synchronization
import Testing

/// Asking the fake server for an item's media segments.
struct MediaSegmentsTests {
    private func session(host: String) throws -> JellyfinSession {
        try JellyfinSession(
            serverURL: #require(URL(string: "https://\(host)/jf")),
            userID: "u1",
            accessToken: "tok",
            identity: ClientIdentity(deviceName: "Test TV", deviceID: "device-1", appVersion: "0.1.0"),
            sessionConfiguration: { MockServer.sessionConfiguration() },
        )
    }

    /// Answers requests for `path` with `reply`, recording the last one.
    private func register(host: String, path: String, reply: MockServer.Reply) -> Recorder {
        let recorder = Recorder()
        MockServer.register(host: host) { request in
            guard request.url?.path() == path else { return nil }
            recorder.last.withLock { $0 = SentRequest(request) }
            return reply
        }
        return recorder
    }

    @Test func `segments come in the order they play, without unknown, foreign or empty ones`() async throws {
        let sent = register(host: "segments.test", path: "/jf/MediaSegments/m1", reply: .json("""
        {"Items":[
         {"Id":"out","ItemId":"m1","Type":"Outro","StartTicks":5000000000,"EndTicks":5500000000},
         {"Id":"in","ItemId":"m1","Type":"Intro","StartTicks":100000000,"EndTicks":400000000},
         {"Id":"unknown","ItemId":"m1","Type":"Unknown","StartTicks":0,"EndTicks":100000000},
         {"Id":"other","ItemId":"m2","Type":"Recap","StartTicks":0,"EndTicks":100000000},
         {"Id":"empty","ItemId":"m1","Type":"Preview","StartTicks":600000000,"EndTicks":600000000},
         {"Id":"untimed","ItemId":"m1","Type":"Commercial"},
         {"Id":"in","ItemId":"m1","Type":"Intro","StartTicks":100000000,"EndTicks":400000000}
        ],"TotalRecordCount":7}
        """))

        let segments = try await session(host: "segments.test").mediaSegments(for: "m1")

        let request = try #require(sent.request)
        #expect(request.method == "GET")
        #expect(request.query.isEmpty)
        #expect(segments == [
            MediaSegment(id: "in", kind: .intro, start: .seconds(10), end: .seconds(40)),
            MediaSegment(id: "out", kind: .outro, start: .seconds(500), end: .seconds(550)),
        ])
    }

    @Test func `item IDs match with or without dashes, and segments without an ID get one`() async throws {
        let itemID = "c7eb95d14156c803611cf4a78ac469f6"
        _ = register(host: "segment-ids.test", path: "/jf/MediaSegments/\(itemID)", reply: .json("""
        {"Items":[
         {"ItemId":"C7EB95D1-4156-C803-611C-F4A78AC469F6","Type":"Recap","StartTicks":0,"EndTicks":50000000},
         {"Id":"credits","Type":"Outro","StartTicks":600000000,"EndTicks":650000000}
        ]}
        """))

        let segments = try await session(host: "segment-ids.test").mediaSegments(for: itemID)

        #expect(segments.map(\.kind) == [.recap, .outro])
        #expect(segments.map(\.id) == ["recap:0:50000000", "credits"])
    }

    @Test func `a segment holds its start but not its end`() {
        let intro = MediaSegment(id: "in", kind: .intro, start: .seconds(10), end: .seconds(40))

        #expect(!intro.contains(.seconds(9)))
        #expect(intro.contains(.seconds(10)))
        #expect(intro.contains(.milliseconds(39999)))
        #expect(!intro.contains(.seconds(40)))
    }

    @Test func `a revoked token signs the user out`() async throws {
        MockServer.register(host: "segments-revoked.test") { _ in .unauthorized }

        await #expect(throws: SessionError.signedOut) {
            try await session(host: "segments-revoked.test").mediaSegments(for: "m1")
        }
    }
}
