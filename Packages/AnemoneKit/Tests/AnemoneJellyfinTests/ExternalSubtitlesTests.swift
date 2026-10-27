import AnemoneJellyfin
import Foundation
import Synchronization
import Testing

/// The subtitle files beside an item's video, as a player that fetches them itself gets them.
struct ExternalSubtitlesTests {
    private func session(host: String) throws -> JellyfinSession {
        try JellyfinSession(
            serverURL: #require(URL(string: "https://\(host)/jf")),
            userID: "u1",
            accessToken: "tok",
            identity: ClientIdentity(deviceName: "Test TV", deviceID: "device-1", appVersion: "0.1.0"),
            sessionConfiguration: { MockServer.sessionConfiguration() },
        )
    }

    private func stream(subtitleStreamIndex: Int? = nil, liveStreamID: String? = nil) throws -> PlaybackStream {
        try PlaybackStream(
            itemID: "m1",
            url: #require(URL(string: "https://jf.test/Videos/m1/stream")),
            method: .directPlay,
            mediaSourceID: "src1",
            liveStreamID: liveStreamID,
            subtitleStreamIndex: subtitleStreamIndex,
        )
    }

    @Test func `the version's external files in the formats asked for come with their URLs`() async throws {
        let sent = Recorder()
        MockServer.register(host: "external-subs.test") { request in
            guard request.url?.path() == "/jf/Items/m1" else { return nil }
            sent.last.withLock { $0 = SentRequest(request) }
            return .json("""
            {"Id":"m1","Name":"Movie","Type":"Movie","MediaSources":[
             {"Id":"other","MediaStreams":[
              {"Index":5,"Type":"Subtitle","Codec":"srt","IsExternal":true,"DisplayTitle":"Other version"}]},
             {"Id":"src1","MediaStreams":[
              {"Index":0,"Type":"Video","Codec":"h264"},
              {"Index":2,"Type":"Subtitle","Codec":"subrip","Language":"spa","DisplayTitle":"Embedded"},
              {"Index":3,"Type":"Subtitle","Codec":"subrip","Language":"eng","IsExternal":true,
               "DisplayTitle":"English - SUBRIP - External"},
              {"Index":4,"Type":"Subtitle","Codec":"ass","Language":"fre","IsExternal":true,
               "DisplayTitle":"French - ASS - External"},
              {"Index":6,"Type":"Subtitle","Codec":"pgssub","IsExternal":true,"DisplayTitle":"Pictures"}
             ]}
            ]}
            """)
        }

        let subtitles = try await session(host: "external-subs.test").externalSubtitles(
            for: stream(subtitleStreamIndex: 4),
            formats: ["subrip", "ass"],
        )

        #expect(try #require(sent.request).method == "GET")
        #expect(subtitles.map(\.title) == ["English - SUBRIP - External", "French - ASS - External"])
        #expect(subtitles.map(\.language) == ["eng", "fre"])
        #expect(subtitles.map(\.isDefault) == [false, true])
        #expect(subtitles.map { $0.url.path() } == [
            "/jf/Videos/m1/src1/Subtitles/3/Stream.subrip",
            "/jf/Videos/m1/src1/Subtitles/4/Stream.ass",
        ])
        #expect(subtitles.allSatisfy { $0.url.queryValues["ApiKey"] == "tok" })
    }

    @Test func `a live stream has none, without asking the server`() async throws {
        let calls = Mutex(0)
        MockServer.register(host: "external-subs-live.test") { _ in
            calls.withLock { $0 += 1 }
            return nil
        }

        let subtitles = try await session(host: "external-subs-live.test").externalSubtitles(
            for: stream(liveStreamID: "live-1"),
            formats: ["subrip"],
        )

        #expect(subtitles.isEmpty)
        #expect(calls.withLock(\.self) == 0)
    }
}
