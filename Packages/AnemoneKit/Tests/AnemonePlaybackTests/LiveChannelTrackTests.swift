import AnemoneCore
import AnemoneJellyfin
@testable import AnemonePlayback
import Foundation
import Synchronization
import Testing

/// Live TV is left to the server, as Wholphin and Swiftfin leave it: the player asks how to play
/// a channel without a version or tracks, since until the server opens the live stream the
/// channel's version is a placeholder, and the server reads track indices only with a version.
@MainActor
struct LiveChannelTrackTests {
    private let engine = TrackEngine()
    private let log = EventLog()
    private let requests = StreamRequestLog()
    private let defaults: UserDefaults
    private let store: TrackChoiceStore

    init() throws {
        let suite = "LiveChannelTrackTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        store = TrackChoiceStore(userID: "u1", defaults: defaults)
    }

    private func menu(_ id: String, in playback: PlaybackController) -> PlayerMenu? {
        playback.accessories.menus.first { $0.id == id }
    }

    @Test func `a channel's menus offer what switches in the player, and nothing is remembered`() async throws {
        let selection = TrackSelection(
            server: TrackSelection.Server(
                // A channel's version is a placeholder without tracks until its live stream opens.
                itemTracks: { id in ItemTracks(itemID: id, sources: [.init(id: id, tracks: [])], isLive: true) },
                profileSettings: { .english },
            ),
            store: store,
            defaults: defaults,
        )
        let playback = PlaybackController(
            request: PlaybackRequest(.item("ch1")),
            engine: engine,
            features: [selection, log],
        ) { [requests] request in
            requests.append(request)
            // A live stream in HLS with the multi-track file's tracks, as the server picked them.
            return PlaybackStream.hls(
                request.itemID,
                TrackRequest(audioIndex: 1, subtitleIndex: 4),
                method: .directStream,
            )
        }

        await playback.start()
        engine.send(.ready)
        _ = await eventually { log.events.contains { $0.hasPrefix("started") } }

        // No version and no tracks, the first time or again, as for a retry.
        #expect(requests.sent.map(\.mediaSourceID) == [nil])
        #expect(requests.all == [nil])
        #expect(await selection.request(for: "ch1", mediaSourceID: "ch1") == nil)
        // HLS carries one audio track; text subtitles switch in the player, while burned-in ones
        // would take another stream.
        #expect(menu("audio", in: playback) == nil)
        #expect(menu("subtitles", in: playback)?.options.map(\.id) == [
            "subtitles.off", "subtitles.4", "subtitles.5", "subtitles.6",
        ])
        try #require(menu("subtitles", in: playback)?.options.first { $0.id == "subtitles.6" }).select()
        #expect(await eventually { engine.selected[.subtitle] == 2 })
        #expect(menu("subtitles", in: playback)?.options.filter(\.isSelected).map(\.id) == ["subtitles.6"])
        #expect(requests.sent.count == 1)
        #expect(store.itemChoice(for: "ch1") == nil)
    }

    @Test func `a channel's PlaybackInfo names no version and no tracks`() async throws {
        let host = "live-channel.test"
        let server = ChannelServer.register(host: host)
        let session = try JellyfinSession(
            serverURL: #require(URL(string: "https://\(host)/jf")),
            userID: "live-user-\(UUID().uuidString)",
            accessToken: "tok",
            identity: ClientIdentity(deviceName: "Test TV", deviceID: "device-1", appVersion: "0.1.0"),
            sessionConfiguration: { ChannelServer.sessionConfiguration() },
        )
        let playback = PlaybackController(session: session, request: PlaybackRequest(.item("ch1")))

        await playback.start()
        await playback.stop()

        // The track menus looked at the channel first.
        #expect(server.sent.map(\.path).contains("/jf/Items/ch1"))
        let info = try #require(server.sent.first { $0.path == "/jf/Items/ch1/PlaybackInfo" })
        let body = try #require(JSONSerialization.jsonObject(with: info.body) as? [String: Any])
        #expect(body["AutoOpenLiveStream"] as? Bool == true)
        #expect(body["MediaSourceId"] == nil)
        #expect(body["AudioStreamIndex"] == nil)
        #expect(body["SubtitleStreamIndex"] == nil)
    }
}

/// A server with one live TV channel, `ch1`, described as Jellyfin describes one before its live
/// stream opens. It answers PlaybackInfo with nothing to play, recording what it was sent.
final class ChannelServer: URLProtocol {
    struct Request {
        let path: String
        let body: Data
    }

    struct Recorder {
        let host: String

        var sent: [Request] {
            ChannelServer.requests.withLock { $0[host] ?? [] }
        }
    }

    private static let requests = Mutex<[String: [Request]]>([:])

    private static let channel = """
    {"Id":"ch1","Name":"Anemone 1","Type":"TvChannel","ChannelType":"TV","MediaType":"Video",
     "MediaSources":[{"Id":"ch1","Type":"Placeholder","Protocol":"Http","IsInfiniteStream":true,
      "MediaStreams":[]}]}
    """

    static func register(host: String) -> Recorder {
        requests.withLock { $0[host] = [] }
        return Recorder(host: host)
    }

    static func sessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ChannelServer.self]
        return configuration
    }

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url, let host = url.host(),
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: 200,
                  httpVersion: nil,
                  headerFields: ["Content-Type": "application/json"],
              )
        else { return }
        let path = url.path()
        Self.requests.withLock { $0[host, default: []].append(Request(path: path, body: Self.body(of: request))) }
        let reply = path.hasSuffix("/Items/ch1") ? Self.channel : #"{"MediaSources":[]}"#
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// URLProtocol sees a request's body as a stream.
    private static func body(of request: URLRequest) -> Data {
        guard let stream = request.httpBodyStream else { return request.httpBody ?? Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
