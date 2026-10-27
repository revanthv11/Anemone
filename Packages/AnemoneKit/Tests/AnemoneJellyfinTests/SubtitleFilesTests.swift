import AnemoneCore
@testable import AnemoneJellyfin
import Foundation
import Testing

/// Fetching a text subtitle stream as a file of its own, for Anemone to draw.
struct SubtitleFilesTests {
    private func session(host: String) throws -> JellyfinSession {
        try JellyfinSession(
            serverURL: #require(URL(string: "https://\(host)/jf")),
            userID: "u1",
            accessToken: "tok",
            identity: ClientIdentity(deviceName: "Test TV", deviceID: "device-1", appVersion: "0.1.0"),
            sessionConfiguration: { MockServer.sessionConfiguration() },
        )
    }

    @Test func `a subtitle stream is fetched whole from the subtitle endpoint`() async throws {
        let recorder = Recorder()
        let body = "1\n00:00:02,000 --> 00:00:06,000\nEnglish SRT · cue 1\n"
        MockServer.register(host: "subtitle-file.test") { request in
            recorder.record(request)
            return MockServer.Reply(status: 200, body: body)
        }
        let request = SubtitleFileRequest(itemID: "m1", mediaSourceID: "ms1", index: 4, format: .srt)

        let file = try await session(host: "subtitle-file.test").subtitleFile(request)

        let sent = try #require(recorder.request)
        #expect(sent.method == "GET")
        #expect(sent.path == "/jf/Videos/m1/ms1/Subtitles/4/Stream.srt")
        // Times from the start of the video, as the server sends them by default.
        #expect(sent.query.isEmpty)
        #expect(file == SubtitleFile(format: .srt, text: body))
    }

    @Test func `a WebVTT track is asked for as WebVTT, and anything else as SRT`() {
        func format(_ codec: String?) -> SubtitleFile.Format {
            let track = MediaTrack(index: 3, kind: .subtitle, codec: codec)
            return SubtitleFileRequest(track, itemID: "m1", mediaSourceID: "ms1").format
        }

        #expect(format("webvtt") == .vtt)
        #expect(format("VTT") == .vtt)
        #expect(format("subrip") == .srt)
        #expect(format("srt") == .srt)
        #expect(format("ass") == .srt)
        #expect(format("mov_text") == .srt)
        #expect(format(nil) == .srt)
        let request = SubtitleFileRequest(MediaTrack(index: 3, kind: .subtitle), itemID: "m1", mediaSourceID: "ms1")
        #expect(request == SubtitleFileRequest(itemID: "m1", mediaSourceID: "ms1", index: 3, format: .srt))
    }

    @Test func `a failed fetch is an error`() async throws {
        MockServer.register(host: "subtitle-missing.test") { _ in MockServer.Reply(status: 404, body: "") }
        let request = SubtitleFileRequest(itemID: "m1", mediaSourceID: "ms1", index: 9, format: .vtt)

        await #expect(throws: (any Error).self) {
            try await session(host: "subtitle-missing.test").subtitleFile(request)
        }
    }

    @Test func `files in UTF-16 or Windows Latin-1 are read too`() {
        #expect(SubtitleFile.decode(Data("Café".utf8)) == "Café")
        let latin1 = Data([0x43, 0x61, 0x66, 0xE9, 0x20, 0x93, 0x71, 0x94])
        #expect(SubtitleFile.decode(latin1) == "Café \u{201C}q\u{201D}")
        let utf16 = Data([0xFF, 0xFE]) + Data("Été".utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })
        #expect(SubtitleFile.decode(utf16) == "Été")
    }
}
