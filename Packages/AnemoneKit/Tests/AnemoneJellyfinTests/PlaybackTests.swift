import AnemoneJellyfin
import Foundation
import JellyfinAPI
import Synchronization
import Testing

/// Asking the fake server how to play an item, and reporting on playback.
struct PlaybackTests {
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
    private func register(host: String, path: String, reply: MockServer.Reply = .json("{}")) -> Recorder {
        let recorder = Recorder()
        MockServer.register(host: host) { request in
            guard request.url?.path() == path else { return nil }
            recorder.last.withLock { $0 = SentRequest(request) }
            return reply
        }
        return recorder
    }

    private static let profile = DeviceProfile(name: "Test profile")

    @Test func `direct play streams the file with the token in the query`() async throws {
        let sent = register(host: "direct.test", path: "/jf/Items/m1/PlaybackInfo", reply: .json("""
        {"PlaySessionId":"ps1","MediaSources":[{"Id":"src1","ETag":"etag1","SupportsDirectPlay":true,
         "SupportsDirectStream":true,"SupportsTranscoding":true,"DefaultAudioStreamIndex":1}]}
        """))

        let stream = try await session(host: "direct.test")
            .playbackStream(for: "m1", profile: Self.profile, maxBitrate: 1000)

        let body = try #require(sent.request).json
        #expect(body["UserId"] as? String == "u1")
        #expect(body["MaxStreamingBitrate"] as? Int == 1000)
        #expect(body["EnableDirectPlay"] as? Bool == true)
        #expect(body["EnableDirectStream"] as? Bool == true)
        #expect(body["EnableTranscoding"] as? Bool == true)
        #expect((body["DeviceProfile"] as? [String: Any])?["Name"] as? String == "Test profile")
        #expect(body["MediaSourceId"] == nil)

        #expect(stream.method == .directPlay)
        #expect(stream.playSessionID == "ps1")
        #expect(stream.mediaSourceID == "src1")
        #expect(stream.audioStreamIndex == 1)
        #expect(stream.url.path() == "/jf/Videos/m1/stream")
        let query = stream.url.queryValues
        #expect(query["static"] == "true")
        #expect(query["mediaSourceId"] == "src1")
        #expect(query["tag"] == "etag1")
        #expect(query["playSessionId"] == "ps1")
        #expect(query["ApiKey"] == "tok")
    }

    @Test func `a remote source plays from where it points`() async throws {
        _ = register(host: "remote.test", path: "/jf/Items/m1/PlaybackInfo", reply: .json("""
        {"PlaySessionId":"ps1","MediaSources":[{"Id":"src1","SupportsDirectPlay":true,"IsRemote":true,
         "Path":"https://cdn.example/film.mp4"}]}
        """))

        let stream = try await session(host: "remote.test")
            .playbackStream(for: "m1", profile: Self.profile, maxBitrate: 1000)

        #expect(stream.url.absoluteString == "https://cdn.example/film.mp4")
    }

    @Test func `direct stream uses the server's HLS address`() async throws {
        _ = register(host: "remux.test", path: "/jf/Items/m1/PlaybackInfo", reply: .json("""
        {"PlaySessionId":"ps1","MediaSources":[{"Id":"src1","SupportsDirectPlay":false,"SupportsDirectStream":true,
         "TranscodingUrl":"/videos/m1/master.m3u8?MediaSourceId=src1&ApiKey=tok&VideoCodec=hevc"}]}
        """))

        let stream = try await session(host: "remux.test")
            .playbackStream(for: "m1", profile: Self.profile, maxBitrate: 1000)

        #expect(stream.method == .directStream)
        #expect(stream.url.path() == "/jf/videos/m1/master.m3u8")
        #expect(stream.url.queryValues["VideoCodec"] == "hevc")
        // The server's token is kept, not added twice.
        #expect(stream.url.queryValues["ApiKey"] == "tok")
    }

    @Test func `falling back to a transcode turns off direct play and stream copying`() async throws {
        let sent = register(host: "transcode.test", path: "/jf/Items/m1/PlaybackInfo", reply: .json("""
        {"PlaySessionId":"ps2","MediaSources":[{"Id":"src1","SupportsDirectPlay":false,"SupportsDirectStream":false,
         "SupportsTranscoding":true,"TranscodingUrl":"/videos/m1/master.m3u8?MediaSourceId=src1"}]}
        """))

        let stream = try await session(host: "transcode.test").playbackStream(
            for: "m1",
            profile: Self.profile,
            maxBitrate: 1000,
            allowsDirect: false,
            mediaSourceID: "src1",
        )

        let body = try #require(sent.request).json
        #expect(body["EnableDirectPlay"] as? Bool == false)
        #expect(body["EnableDirectStream"] as? Bool == false)
        #expect(body["AllowVideoStreamCopy"] as? Bool == false)
        #expect(body["AllowAudioStreamCopy"] as? Bool == false)
        #expect(body["MediaSourceId"] as? String == "src1")
        #expect(stream.method == .transcode)
        // A playlist without the token gets it, so AVPlayer's requests are signed in.
        #expect(stream.url.queryValues["ApiKey"] == "tok")
    }

    @Test func `the server's refusal comes back as a playback error`() async throws {
        _ = register(host: "refused.test", path: "/jf/Items/m1/PlaybackInfo", reply: .json("""
        {"ErrorCode":"NotAllowed","MediaSources":[]}
        """))

        await #expect(throws: PlaybackError.notAllowed) {
            try await session(host: "refused.test").playbackStream(for: "m1", profile: Self.profile, maxBitrate: 1)
        }
    }

    @Test func `a source with nothing to play is an error`() async throws {
        _ = register(host: "empty.test", path: "/jf/Items/m1/PlaybackInfo", reply: .json("""
        {"PlaySessionId":"ps1","MediaSources":[{"Id":"src1","SupportsDirectPlay":false}]}
        """))

        await #expect(throws: PlaybackError.nothingToPlay) {
            try await session(host: "empty.test").playbackStream(for: "m1", profile: Self.profile, maxBitrate: 1)
        }
    }

    @Test func `reports carry the play session and the position in ticks`() async throws {
        let started = register(host: "report.test", path: "/jf/Sessions/Playing")
        let session = try session(host: "report.test")
        let stream = PlaybackStream(
            itemID: "m1",
            url: URL(filePath: "/"),
            method: .directStream,
            playSessionID: "ps1",
            mediaSourceID: "src1",
            audioStreamIndex: 1,
            subtitleStreamIndex: 3,
        )

        try await session.reportPlaybackStart(stream, at: .init(position: .seconds(90.5), isPaused: false))

        let start = try #require(started.request).json
        #expect(start["ItemId"] as? String == "m1")
        #expect(start["PlaySessionId"] as? String == "ps1")
        #expect(start["MediaSourceId"] as? String == "src1")
        #expect(start["PlayMethod"] as? String == "DirectStream")
        #expect(start["PositionTicks"] as? Int == 905_000_000)
        #expect(start["IsPaused"] as? Bool == false)
        #expect(start["AudioStreamIndex"] as? Int == 1)
        #expect(start["SubtitleStreamIndex"] as? Int == 3)
    }

    @Test func `progress says whether playback is paused`() async throws {
        let sent = register(host: "progress.test", path: "/jf/Sessions/Playing/Progress")
        let stream = PlaybackStream(itemID: "m1", url: URL(filePath: "/"), method: .directPlay, playSessionID: "ps1")

        try await session(host: "progress.test")
            .reportPlaybackProgress(stream, at: .init(position: .seconds(2), isPaused: true))

        let body = try #require(sent.request).json
        #expect(body["PositionTicks"] as? Int == 20_000_000)
        #expect(body["IsPaused"] as? Bool == true)
        #expect(body["PlayMethod"] as? String == "DirectPlay")
    }

    @Test func `stopping saves the final position`() async throws {
        let sent = register(host: "stop.test", path: "/jf/Sessions/Playing/Stopped")
        let stream = PlaybackStream(itemID: "m1", url: URL(filePath: "/"), method: .transcode, playSessionID: "ps1")

        try await session(host: "stop.test").reportPlaybackStopped(stream, at: .seconds(3600))

        let body = try #require(sent.request).json
        #expect(body["ItemId"] as? String == "m1")
        #expect(body["PlaySessionId"] as? String == "ps1")
        #expect(body["PositionTicks"] as? Int == 36_000_000_000)
    }
}
