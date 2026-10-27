import AnemoneCore
import AnemoneJellyfin
import Foundation
import JellyfinAPI
import Testing

/// Fetching what choosing tracks needs, and asking for the chosen tracks.
struct MediaStreamsTests {
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

    @Test func `an episode's tracks come with its season and series`() async throws {
        let sent = register(host: "episode-tracks.test", path: "/jf/Items/e2", reply: .json("""
        {"Id":"e2","Type":"Episode","SeriesId":"show","SeasonId":"s2","ParentId":"s2","MediaSources":[
         {"Id":"src1","MediaStreams":[
          {"Index":0,"Type":"Video","Codec":"h264"},
          {"Index":1,"Type":"Audio","Codec":"aac","Language":"eng","Channels":2,"IsDefault":true,
           "DisplayTitle":"English - AAC - Stereo - Default"},
          {"Index":2,"Type":"Audio","Codec":"ac3","Language":"fre","Channels":6},
          {"Index":3,"Type":"Subtitle","Codec":"subrip","Language":"eng","IsForced":true,"IsTextSubtitleStream":true,
           "Title":"Forced"},
          {"Index":4,"Type":"Subtitle","Codec":"PGSSUB","Language":"ger","IsTextSubtitleStream":false,
           "IsHearingImpaired":true},
          {"Index":5,"Type":"Subtitle","Codec":"srt","Language":"spa","IsExternal":true,"IsTextSubtitleStream":true}
         ]},
         {"Id":"src2","MediaStreams":[]}
        ]}
        """))

        let tracks = try await session(host: "episode-tracks.test").itemTracks(for: "e2")

        #expect(try #require(sent.request).method == "GET")
        #expect(tracks.seriesID == "show")
        #expect(tracks.seasonID == "s2")
        #expect(tracks.sources.map(\.id) == ["src1", "src2"])
        #expect(tracks.source(nil)?.id == "src1")
        #expect(tracks.source("src2")?.tracks == [])
        #expect(tracks.source("gone") == nil)
        let source = try #require(tracks.source("src1"))
        #expect(source.tracks.map(\.index) == [1, 2, 3, 4, 5])
        #expect(source.tracks[0] == MediaTrack(
            index: 1,
            kind: .audio,
            language: "eng",
            displayTitle: "English - AAC - Stereo - Default",
            codec: "aac",
            channels: 2,
            isDefault: true,
            isText: false,
        ))
        #expect(source.tracks[2].isForced)
        #expect(source.tracks[2].title == "Forced")
        #expect(source.tracks[3].isPicture)
        #expect(source.tracks[3].isHearingImpaired)
        #expect(source.tracks[4].isExternal)
    }

    @Test func `a movie's choices aren't kept for its folder`() async throws {
        _ = register(host: "movie-tracks.test", path: "/jf/Items/m1", reply: .json("""
        {"Id":"m1","Type":"Movie","ParentId":"library","MediaSources":[{"Id":"m1","MediaStreams":[]}]}
        """))

        let tracks = try await session(host: "movie-tracks.test").itemTracks(for: "m1")

        #expect(tracks.seriesID == nil)
        #expect(tracks.seasonID == nil)
    }

    @Test func `the Jellyfin profile's language and subtitle settings`() async throws {
        _ = register(host: "profile-tracks.test", path: "/jf/Users/Me", reply: .json("""
        {"Id":"u1","Name":"Alice","Configuration":{"AudioLanguagePreference":"jpn","SubtitleLanguagePreference":"eng",
         "SubtitleMode":"Smart","PlayDefaultAudioTrack":true}}
        """))

        let settings = try await session(host: "profile-tracks.test").profileTrackSettings()

        #expect(settings == ProfileTrackSettings(audioLanguage: "jpn", subtitleLanguage: "eng", subtitleMode: .smart))
    }

    @Test func `the server's languages, by name, once each`() async throws {
        _ = register(host: "cultures-tracks.test", path: "/jf/Localization/Cultures", reply: .json("""
        [{"DisplayName":"French","ThreeLetterISOLanguageName":"fre","ThreeLetterISOLanguageNames":["fre","fra"]},
         {"DisplayName":"English","ThreeLetterISOLanguageName":"eng"},
         {"DisplayName":"English (United Kingdom)","ThreeLetterISOLanguageName":"eng"},
         {"DisplayName":"Invariant","ThreeLetterISOLanguageName":""}]
        """))

        let languages = try await session(host: "cultures-tracks.test").languages()

        #expect(languages == [
            ServerLanguage(code: "eng", name: "English"),
            ServerLanguage(code: "fre", name: "French"),
        ])
    }

    @Test func `the PlaybackInfo request asks for the chosen tracks and says how each subtitle comes`() async throws {
        let sent = register(host: "choice-tracks.test", path: "/jf/Items/m1/PlaybackInfo", reply: .json("""
        {"PlaySessionId":"ps1","MediaSources":[{"Id":"src1","SupportsDirectPlay":false,"SupportsDirectStream":true,
         "TranscodingUrl":"/videos/m1/master.m3u8?AudioStreamIndex=2","DefaultAudioStreamIndex":2,
         "DefaultSubtitleStreamIndex":4,"MediaStreams":[
          {"Index":2,"Type":"Audio","Language":"fre"},
          {"Index":3,"Type":"Subtitle","Codec":"subrip","DeliveryMethod":"Hls","IsTextSubtitleStream":true},
          {"Index":4,"Type":"Subtitle","Codec":"PGSSUB","DeliveryMethod":"Encode","IsTextSubtitleStream":false}
         ]}]}
        """))

        let stream = try await session(host: "choice-tracks.test").playbackStream(
            for: "m1",
            profile: DeviceProfile(name: "Test"),
            maxBitrate: 1000,
            audioStreamIndex: 2,
            subtitleStreamIndex: 4,
        )

        let body = try #require(sent.request).json
        #expect(body["AudioStreamIndex"] as? Int == 2)
        #expect(body["SubtitleStreamIndex"] as? Int == 4)
        #expect(stream.audioStreamIndex == 2)
        #expect(stream.subtitleStreamIndex == 4)
        #expect(stream.tracks.map(\.delivery) == [nil, .hls, .burnedIn])
    }

    @Test func `without a choice the server picks`() async throws {
        let sent = register(host: "nochoice-tracks.test", path: "/jf/Items/m1/PlaybackInfo", reply: .json("""
        {"PlaySessionId":"ps1","MediaSources":[{"Id":"src1","SupportsDirectPlay":true}]}
        """))

        _ = try await session(host: "nochoice-tracks.test")
            .playbackStream(for: "m1", profile: DeviceProfile(name: "Test"), maxBitrate: 1000)

        let body = try #require(sent.request).json
        #expect(body["AudioStreamIndex"] == nil)
        #expect(body["SubtitleStreamIndex"] == nil)
    }
}
