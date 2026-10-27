import AnemoneJellyfin
import Foundation
import Synchronization
import Testing

/// Searching for and downloading subtitles through the fake server, and finding an item's video
/// for the player choice.
struct RemoteSubtitlesTests {
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

    @Test func `a search sorts matches of the file first, then by rating and by downloads`() async throws {
        let path = "/jf/Items/m1/RemoteSearch/Subtitles/eng"
        let sent = register(host: "subs-search.test", path: path, reply: .json("""
        [
         {"Id":"low","Name":"Low rated","ProviderName":"OpenSubtitles","Format":"srt",
          "CommunityRating":2,"DownloadCount":900},
         {"Id":"popular","Name":"Popular","CommunityRating":8,"DownloadCount":5000},
         {"Id":"hash","Name":"Exact","IsHashMatch":true,"CommunityRating":1,"DownloadCount":3},
         {"Name":"No ID"},
         {"Id":"rated","Name":"Rated","CommunityRating":8,"DownloadCount":100,"Forced":true,
          "HearingImpaired":true,"MachineTranslated":true}
        ]
        """))

        let found = try await session(host: "subs-search.test").searchSubtitles(for: "m1", language: "eng")

        let request = try #require(sent.request)
        #expect(request.method == "GET")
        #expect(found.map(\.id) == ["hash", "popular", "rated", "low"])
        #expect(found.last == RemoteSubtitle(
            id: "low",
            name: "Low rated",
            provider: "OpenSubtitles",
            format: "srt",
            rating: 2,
            downloads: 900,
        ))
        #expect(found[2].isForced)
        #expect(found[2].isHearingImpaired)
        #expect(found[2].isMachineTranslated)
    }

    @Test func `downloading posts the subtitle's ID for the item`() async throws {
        let sent = register(
            host: "subs-download.test",
            path: "/jf/Items/m1/RemoteSearch/Subtitles/opensubtitles-123",
            reply: .json(""),
        )

        try await session(host: "subs-download.test").downloadSubtitles("opensubtitles-123", for: "m1")

        let request = try #require(sent.request)
        #expect(request.method == "POST")
    }

    @Test func `the new download is the external stream that wasn't there before`() async throws {
        let calls = Mutex(0)
        MockServer.register(host: "subs-new.test") { request in
            guard request.url?.path() == "/jf/Items/m1" else { return nil }
            let call = calls.withLock { count in
                count += 1
                return count
            }
            let downloaded = call >= 2
                ? #",{"Index":4,"Type":"Subtitle","Codec":"srt","Language":"eng","IsExternal":true,"# +
                #""Path":"/media/m1.en.srt","DisplayTitle":"English - SRT - External"}"#
                : ""
            return .json("""
            {"Id":"m1","Name":"Movie","Type":"Movie","MediaSources":[
             {"Id":"other","MediaStreams":[]},
             {"Id":"src1","MediaStreams":[
              {"Index":0,"Type":"Video","Codec":"h264"},
              {"Index":2,"Type":"Subtitle","Codec":"ass","Language":"spa","Title":"Signs"},
              {"Index":3,"Type":"Subtitle","Codec":"srt","Language":"fre","IsExternal":true,"Path":"/media/m1.fr.srt"}
              \(downloaded)
             ]}
            ]}
            """)
        }
        let session = try session(host: "subs-new.test")

        let known = try await session.subtitleStreams(of: "m1", mediaSourceID: "src1")
        let new = try await session.newSubtitleStream(
            of: "m1",
            mediaSourceID: "src1",
            besides: known,
            interval: .milliseconds(1),
        )

        #expect(known.map(\.index) == [2, 3])
        #expect(known.first == SubtitleStream(index: 2, title: "Signs", language: "spa", codec: "ass"))
        #expect(new == SubtitleStream(
            index: 4,
            title: "English - SRT - External",
            language: "eng",
            codec: "srt",
            isExternal: true,
            path: "/media/m1.en.srt",
        ))
    }

    /// The server can leave paths out; an external stream that was there before isn't the
    /// download, even when the download looks just like it.
    @Test func `an external stream without a path that was there before isn't the new download`() async throws {
        let calls = Mutex(0)
        MockServer.register(host: "subs-no-path.test") { request in
            guard request.url?.path() == "/jf/Items/m1" else { return nil }
            let call = calls.withLock { count in
                count += 1
                return count
            }
            let english = #"{"Type":"Subtitle","Codec":"srt","Language":"eng","IsExternal":true,"# +
                #""DisplayTitle":"English - SRT - External","Index":"#
            let streams = [english + "3}"] + (call >= 3 ? [english + "4}"] : [])
            return .json("""
            {"Id":"m1","Name":"Movie","Type":"Movie","MediaSources":[
             {"Id":"m1","MediaStreams":[\(streams.joined(separator: ","))]}
            ]}
            """)
        }
        let session = try session(host: "subs-no-path.test")

        let known = try await session.subtitleStreams(of: "m1", mediaSourceID: "m1")
        let new = try await session.newSubtitleStream(
            of: "m1",
            mediaSourceID: "m1",
            besides: known,
            interval: .milliseconds(1),
        )

        #expect(known.map(\.index) == [3])
        #expect(new?.index == 4)
        #expect(calls.withLock(\.self) == 3)
    }

    @Test func `waiting for a download gives up after four tries`() async throws {
        let calls = Mutex(0)
        MockServer.register(host: "subs-slow.test") { _ in
            calls.withLock { $0 += 1 }
            return .json(#"{"Id":"m1","Name":"Movie","Type":"Movie","MediaSources":[{"Id":"m1","MediaStreams":[]}]}"#)
        }

        let new = try await session(host: "subs-slow.test")
            .newSubtitleStream(of: "m1", mediaSourceID: "m1", besides: [], interval: .milliseconds(1))

        #expect(new == nil)
        #expect(calls.withLock(\.self) == 4)
    }

    @Test func `a subtitle stream's URL names the version, index and format, with the token`() throws {
        let stream = SubtitleStream(index: 4, title: "English", codec: "srt", isExternal: true)

        let url = try #require(try session(host: "subs-url.test").subtitleURL(
            for: stream,
            of: "m1",
            mediaSourceID: "src1",
        ))

        #expect(url.path() == "/jf/Videos/m1/src1/Subtitles/4/Stream.srt")
        #expect(url.queryValues["ApiKey"] == "tok")
    }

    @Test func `a version's video says whether it's HDR, Dolby Vision or 4K`() async throws {
        MockServer.register(host: "item-video.test") { request in
            guard request.url?.path() == "/jf/Items/m1" else { return nil }
            return .json("""
            {"Id":"m1","Name":"Movie","Type":"Movie","MediaSources":[
             {"Id":"sdr","MediaStreams":[{"Index":0,"Type":"Video","VideoRange":"SDR","VideoRangeType":"SDR",
              "Width":1920,"Height":1080}]},
             {"Id":"hdr","MediaStreams":[{"Index":0,"Type":"Video","VideoRange":"HDR","VideoRangeType":"HDR10",
              "Width":3840,"Height":1600}]},
             {"Id":"dv","MediaStreams":[{"Index":0,"Type":"Video","VideoRange":"SDR","VideoRangeType":"DOVIWithSDR",
              "Width":1920,"Height":1080}]},
             {"Id":"audio","MediaStreams":[{"Index":0,"Type":"Audio"}]}
            ]}
            """)
        }
        let session = try session(host: "item-video.test")

        #expect(try await session.itemVideo(of: "m1") == ItemVideo(isHDR: false, is4K: false))
        #expect(try await session.itemVideo(of: "m1", mediaSourceID: "hdr") == ItemVideo(isHDR: true, is4K: true))
        #expect(try await session.itemVideo(of: "m1", mediaSourceID: "dv") == ItemVideo(isHDR: true, is4K: false))
        #expect(try await session.itemVideo(of: "m1", mediaSourceID: "audio") == nil)
    }
}
