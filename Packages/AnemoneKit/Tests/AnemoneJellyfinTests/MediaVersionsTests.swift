@testable import AnemoneJellyfin
import Foundation
import JellyfinAPI
import Synchronization
import Testing

/// An item's versions from the fake server, and remembering which one the user picked.
struct MediaVersionsTests {
    private func session(host: String) throws -> JellyfinSession {
        try JellyfinSession(
            serverURL: #require(URL(string: "https://\(host)/jf")),
            userID: "u1",
            accessToken: "tok",
            identity: ClientIdentity(deviceName: "Test TV", deviceID: "device-1", appVersion: "0.1.0"),
            sessionConfiguration: { MockServer.sessionConfiguration() },
        )
    }

    private func register(host: String, path: String, reply: MockServer.Reply) -> Recorder {
        let recorder = Recorder()
        MockServer.register(host: host) { request in
            guard request.url?.path() == path else { return nil }
            recorder.last.withLock { $0 = SentRequest(request) }
            return reply
        }
        return recorder
    }

    @Test func `versions are the item's media sources, named as Wholphin names them`() async throws {
        let sent = register(host: "versions.test", path: "/jf/Items/m1", reply: .json("""
        {"Id":"m1","Name":"Film","Type":"Movie","MediaSources":[
         {"Id":"s4k","Name":"2160p","Bitrate":40000000,"RunTimeTicks":66000000000,"MediaStreams":[
          {"Type":"Audio","Codec":"eac3"},
          {"Type":"Video","Codec":"HEVC","Width":3840,"Height":2160,"RealFrameRate":23.976,
           "VideoRangeType":"HDR10","DisplayTitle":"4K HEVC HDR10"}]},
         {"Id":"s1080","Path":"/media/Film/Film - 1080p.mkv","MediaStreams":[
          {"Type":"Video","Codec":"h264","AverageFrameRate":25,"VideoRangeType":"SDR"}]},
         {"Name":"No ID"},
         {"Id":"bare"}]}
        """))

        let versions = try await session(host: "versions.test").mediaVersions(of: "m1")

        let request = try #require(sent.request)
        #expect(request.method == "GET")
        #expect(request.query["userId"] == "u1")
        #expect(versions.map(\.id) == ["s4k", "s1080", "bare"])
        #expect(versions.map(\.name) == ["2160p", "Film - 1080p", "bare"])
        let uhd = try #require(versions.first)
        #expect(uhd.bitrate == 40_000_000)
        #expect(uhd.runtime == .seconds(6600))
        #expect(uhd.video == MediaVersion.Video(
            codec: "hevc",
            width: 3840,
            height: 2160,
            frameRate: 23.976,
            range: .hdr10,
            title: "4K HEVC HDR10",
        ))
        // Without the real frame rate, the average.
        #expect(versions[1].video?.frameRate == 25)
        #expect(versions[2].video == nil)
    }

    @Test func `an item without media sources has no versions`() async throws {
        _ = register(host: "noversions.test", path: "/jf/Items/f1", reply: .json(#"{"Id":"f1","Type":"Folder"}"#))

        #expect(try await session(host: "noversions.test").mediaVersions(of: "f1").isEmpty)
    }

    @Test func `a picked version is remembered for the user and the item`() throws {
        let choices = try Self.choices()

        choices.choose("s4k", for: "m1", userID: "u1")
        choices.choose("s1080", for: "m2", userID: "u1")
        choices.choose("other", for: "m1", userID: "u2")
        choices.choose("s1080", for: "m1", userID: "u1")

        #expect(choices.choice(for: "m1", userID: "u1") == "s1080")
        #expect(choices.choice(for: "m2", userID: "u1") == "s1080")
        #expect(choices.choice(for: "m1", userID: "u2") == "other")
        #expect(choices.choice(for: "m3", userID: "u1") == nil)

        choices.forget("m1", userID: "u1")
        #expect(choices.choice(for: "m1", userID: "u1") == nil)
        #expect(choices.choice(for: "m1", userID: "u2") == "other")
    }

    @Test func `only the latest choices are kept`() throws {
        let choices = try Self.choices()

        for number in 0 ..< MediaVersionChoices.limit + 5 {
            choices.choose("v\(number)", for: "m\(number)", userID: "u1")
        }

        #expect(choices.choice(for: "m0", userID: "u1") == nil)
        #expect(choices.choice(for: "m4", userID: "u1") == nil)
        #expect(choices.choice(for: "m5", userID: "u1") == "v5")
        // Picking again makes it the newest.
        choices.choose("again", for: "m5", userID: "u1")
        choices.choose("new", for: "new", userID: "u1")
        #expect(choices.choice(for: "m5", userID: "u1") == "again")
        #expect(choices.choice(for: "m6", userID: "u1") == nil)
    }

    /// A server whose item `m1` has the versions `s4k` and `s1080`, answering PlaybackInfo as
    /// Jellyfin does: for a version it doesn't have, with none and no compatible stream.
    private func versionsServer(host: String) -> PlaybackInfoLog {
        let sent = PlaybackInfoLog()
        MockServer.register(host: host) { request in
            guard request.url?.path() == "/jf/Items/m1/PlaybackInfo" else { return nil }
            let request = SentRequest(request)
            sent.all.withLock { $0.append(request) }
            let asked = request.json["MediaSourceId"] as? String
            let versions: [String] = ["s4k", "s1080"].filter { asked == nil || $0 == asked }
            guard !versions.isEmpty else {
                return .json(#"{"MediaSources":[],"ErrorCode":"NoCompatibleStream"}"#)
            }
            let sources = versions.map { #"{"Id":"\#($0)","SupportsDirectPlay":true}"# }
            return .json(#"{"PlaySessionId":"ps1","MediaSources":[\#(sources.joined(separator: ","))]}"#)
        }
        return sent
    }

    private static let profile = DeviceProfile(name: "Test profile")

    @Test func `the picked version plays`() async throws {
        let sent = versionsServer(host: "picked.test")
        let choices = try Self.choices()
        choices.choose("s1080", for: "m1", userID: "u1")

        let stream = try await session(host: "picked.test")
            .playbackStream(forPickedVersionOf: "m1", profile: Self.profile, maxBitrate: 1000, choices: choices)

        #expect(sent.requests.map { $0.json["MediaSourceId"] as? String } == ["s1080"])
        #expect(stream.mediaSourceID == "s1080")
        #expect(choices.choice(for: "m1", userID: "u1") == "s1080")
    }

    @Test func `a picked version gone from the server is forgotten, and the first plays`() async throws {
        let sent = versionsServer(host: "gone.test")
        let choices = try Self.choices()
        choices.choose("s720", for: "m1", userID: "u1")

        let stream = try await session(host: "gone.test")
            .playbackStream(forPickedVersionOf: "m1", profile: Self.profile, maxBitrate: 1000, choices: choices)

        let bodies = sent.requests.map(\.json)
        #expect(bodies.count == 2)
        #expect(bodies.first?["MediaSourceId"] as? String == "s720")
        #expect(bodies.last?["MediaSourceId"] == nil)
        #expect(stream.mediaSourceID == "s4k")
        #expect(choices.choice(for: "m1", userID: "u1") == nil)
    }

    @Test func `without a pick, the server's first version plays`() async throws {
        let sent = versionsServer(host: "nopick.test")

        let stream = try await session(host: "nopick.test")
            .playbackStream(forPickedVersionOf: "m1", profile: Self.profile, maxBitrate: 1000, choices: Self.choices())

        #expect(sent.requests.count == 1)
        #expect(sent.requests.first?.json["MediaSourceId"] == nil)
        #expect(stream.mediaSourceID == "s4k")
    }

    @Test func `a picked version the server refuses to play is an error, not forgotten`() async throws {
        MockServer.register(host: "refusedversion.test") { _ in
            .json(#"{"MediaSources":[],"ErrorCode":"NotAllowed"}"#)
        }
        let choices = try Self.choices()
        choices.choose("s1080", for: "m1", userID: "u1")

        await #expect(throws: PlaybackError.notAllowed) {
            try await session(host: "refusedversion.test")
                .playbackStream(forPickedVersionOf: "m1", profile: Self.profile, maxBitrate: 1000, choices: choices)
        }
        #expect(choices.choice(for: "m1", userID: "u1") == "s1080")
    }

    /// A store of its own, empty.
    private static func choices() throws -> MediaVersionChoices {
        let suite = "MediaVersionsTests.\(UUID().uuidString)"
        try #require(UserDefaults(suiteName: suite)).removePersistentDomain(forName: suite)
        return MediaVersionChoices(suiteName: suite)
    }
}

/// Every PlaybackInfo request a fake server saw, in order.
private final class PlaybackInfoLog: Sendable {
    let all = Mutex<[SentRequest]>([])

    var requests: [SentRequest] {
        all.withLock(\.self)
    }
}
