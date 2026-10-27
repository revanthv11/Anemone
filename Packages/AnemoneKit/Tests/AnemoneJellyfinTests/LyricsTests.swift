import AnemoneJellyfin
import Foundation
import Synchronization
import Testing

/// A song's lyrics from the fake server, and finding the line being sung.
struct LyricsTests {
    private func session(host: String) throws -> JellyfinSession {
        try JellyfinSession(
            serverURL: #require(URL(string: "https://\(host)/jf")),
            userID: "u1",
            accessToken: "tok",
            identity: ClientIdentity(deviceName: "Test TV", deviceID: "device-1", appVersion: "0.1.0"),
            sessionConfiguration: { MockServer.sessionConfiguration() },
        )
    }

    @Test func `synced lyrics come with their start times and offset`() async throws {
        let sent = Recorder()
        MockServer.register(host: "music-lyrics.test") { request in
            guard request.url?.path() == "/jf/Audio/s1/Lyrics" else { return nil }
            sent.last.withLock { $0 = SentRequest(request) }
            return .json("""
            {"Metadata":{"IsSynced":true,"Offset":5000000},"Lyrics":[
             {"Text":"First line","Start":20000000},{"Text":"Second line","Start":75000000},{"Start":580000000}
            ]}
            """)
        }

        let lyrics = try #require(try await session(host: "music-lyrics.test").lyrics(for: "s1"))

        #expect(try #require(sent.request).method == "GET")
        #expect(lyrics.isSynced)
        #expect(lyrics.offset == .milliseconds(500))
        #expect(lyrics.lines == [
            Lyrics.Line(start: .seconds(2), text: "First line"),
            Lyrics.Line(start: .milliseconds(7500), text: "Second line"),
            Lyrics.Line(start: .seconds(58), text: ""),
        ])
    }

    @Test func `a song without lyrics has none`() async throws {
        MockServer.register(host: "music-no-lyrics.test") { _ in MockServer.Reply(status: 404, body: "") }
        MockServer.register(host: "music-empty-lyrics.test") { _ in .json(#"{"Lyrics":[]}"#) }

        #expect(try await session(host: "music-no-lyrics.test").lyrics(for: "s1") == nil)
        #expect(try await session(host: "music-empty-lyrics.test").lyrics(for: "s1") == nil)
    }

    @Test func `the current line is the last one that has started, counting the offset`() {
        let lyrics = Lyrics(
            lines: [
                Lyrics.Line(start: .seconds(2), text: "One"),
                Lyrics.Line(start: .seconds(7), text: "Two"),
                Lyrics.Line(start: .seconds(13), text: "Three"),
            ],
            offset: .seconds(1),
        )

        #expect(lyrics.lineIndex(at: .zero) == nil)
        #expect(lyrics.lineIndex(at: .seconds(1)) == 0)
        #expect(lyrics.lineIndex(at: .seconds(5)) == 0)
        #expect(lyrics.lineIndex(at: .seconds(6)) == 1)
        #expect(lyrics.lineIndex(at: .seconds(100)) == 2)
    }

    @Test func `plain lyrics have no current line`() {
        let lyrics = Lyrics(lines: [Lyrics.Line(start: nil, text: "Words"), Lyrics.Line(start: nil, text: "More")])

        #expect(!lyrics.isSynced)
        #expect(lyrics.lineIndex(at: .seconds(30)) == nil)
    }

    @Test func `a revoked token signs the user out`() async throws {
        MockServer.register(host: "lyrics-revoked.test") { _ in .unauthorized }

        await #expect(throws: SessionError.signedOut) {
            try await session(host: "lyrics-revoked.test").lyrics(for: "s1")
        }
    }
}
