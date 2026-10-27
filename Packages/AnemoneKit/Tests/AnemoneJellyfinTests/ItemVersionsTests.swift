import AnemoneJellyfin
import Foundation
import Testing

/// The versions an item page's item comes with, so the Version button asks the server nothing
/// itself.
struct ItemVersionsTests {
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

    private static let sources = """
    "MediaSources":[
     {"Id":"s4k","Name":"2160p","MediaStreams":[{"Type":"Video","Codec":"hevc","RealFrameRate":23.976}]},
     {"Id":"s1080","Name":"1080p"}]
    """

    @Test func `a movie page's item comes with its versions`() async throws {
        _ = register(host: "item-versions.test", path: "/jf/Items/m1", reply: .json("""
        {"Id":"m1","Name":"Film","Type":"Movie",\(Self.sources)}
        """))

        let movie = try await session(host: "item-versions.test").itemDetails(id: "m1")

        #expect(movie.versions.map(\.id) == ["s4k", "s1080"])
        #expect(movie.versions.map(\.name) == ["2160p", "1080p"])
        #expect(movie.versions.first?.video?.frameRate == 23.976)
    }

    @Test func `a season's episodes come with their versions`() async throws {
        let sent = register(host: "episode-versions.test", path: "/jf/Shows/s1/Episodes", reply: .json("""
        {"Items":[
         {"Id":"e1","Name":"Pilot","Type":"Episode",\(Self.sources)},
         {"Id":"e2","Name":"Second","Type":"Episode","MediaSources":[{"Id":"only"}]}]}
        """))

        let episodes = try await session(host: "episode-versions.test").episodes(ofSeries: "s1", season: "sn1")

        #expect(episodes.map { $0.versions.map(\.id) } == [["s4k", "s1080"], ["only"]])
        let fields = try #require(sent.request).query["fields"]?.split(separator: ",") ?? []
        #expect(fields.contains("MediaSources"))
        #expect(fields.contains("People"))
    }

    @Test func `an item without media sources has no versions`() async throws {
        _ = register(host: "no-item-versions.test", path: "/jf/Items/f1", reply: .json("""
        {"Id":"f1","Name":"Show","Type":"Series"}
        """))

        #expect(try await session(host: "no-item-versions.test").itemDetails(id: "f1").versions.isEmpty)
    }
}
