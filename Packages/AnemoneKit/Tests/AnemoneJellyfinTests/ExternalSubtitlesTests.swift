import AnemoneCore
import AnemoneJellyfin
import Foundation
import JellyfinAPI
import Testing

/// The subtitles PlaybackInfo delivers as External, as a player that fetches them itself gets
/// them.
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

    @Test func `the streams PlaybackInfo delivers as External come with URLs like its DeliveryUrl`() async throws {
        MockServer.register(host: "external-subs.test") { request in
            guard request.url?.path() == "/jf/Items/m1/PlaybackInfo" else { return nil }
            return .json("""
            {"PlaySessionId":"ps1","MediaSources":[{"Id":"src1","SupportsDirectPlay":true,
             "DefaultSubtitleStreamIndex":4,"MediaStreams":[
              {"Index":0,"Type":"Video","Codec":"h264"},
              {"Index":2,"Type":"Subtitle","Codec":"subrip","Language":"spa","DisplayTitle":"Embedded",
               "IsTextSubtitleStream":true,"DeliveryMethod":"Embed"},
              {"Index":3,"Type":"Subtitle","Codec":"subrip","Language":"eng","IsExternal":true,
               "IsTextSubtitleStream":true,"DisplayTitle":"English - SUBRIP - External","DeliveryMethod":"External",
               "DeliveryUrl":"/Videos/m1/src1/Subtitles/3/0/Stream.subrip?ApiKey=tok"},
              {"Index":4,"Type":"Subtitle","Codec":"ass","Language":"fre","IsExternal":true,
               "IsTextSubtitleStream":true,"DisplayTitle":"French - ASS - External","DeliveryMethod":"External",
               "DeliveryUrl":"/Videos/m1/src1/Subtitles/4/0/Stream.ass?ApiKey=tok"},
              {"Index":5,"Type":"Subtitle","Codec":"mov_text","IsExternal":true,"IsTextSubtitleStream":true,
               "DisplayTitle":"Converted","DeliveryMethod":"External",
               "DeliveryUrl":"/Videos/m1/src1/Subtitles/5/0/Stream.vtt?ApiKey=tok"},
              {"Index":6,"Type":"Subtitle","Codec":"pgssub","IsExternal":true,"IsTextSubtitleStream":false,
               "DisplayTitle":"Pictures","DeliveryMethod":"Encode"}
             ]}]}
            """)
        }
        let session = try session(host: "external-subs.test")
        let stream = try await session.playbackStream(for: "m1", profile: DeviceProfile(name: "MPV"), maxBitrate: 1000)

        let subtitles = session.externalSubtitles(of: stream, formats: ["subrip", "ass"])

        #expect(subtitles.map(\.title) == ["English - SUBRIP - External", "French - ASS - External", "Converted"])
        #expect(subtitles.map(\.language) == ["eng", "fre", nil])
        #expect(subtitles.map(\.isDefault) == [false, true, false])
        #expect(subtitles.map { $0.url.path() } == [
            "/jf/Videos/m1/src1/Subtitles/3/Stream.subrip",
            "/jf/Videos/m1/src1/Subtitles/4/Stream.ass",
            "/jf/Videos/m1/src1/Subtitles/5/Stream.srt",
        ])
        #expect(subtitles.allSatisfy { $0.url.queryValues["ApiKey"] == "tok" })
    }

    @Test func `a stream without External subtitles has none`() throws {
        let stream = try PlaybackStream(
            itemID: "m1",
            url: #require(URL(string: "https://jf.test/Videos/m1/stream")),
            method: .directPlay,
            tracks: [MediaTrack(index: 2, kind: .subtitle, codec: "subrip", delivery: .embedded)],
        )

        #expect(try session(host: "external-subs-none.test").externalSubtitles(of: stream, formats: ["subrip"]).isEmpty)
    }
}
