import AnemoneCore
@testable import AnemoneJellyfin
@testable import AnemonePlayback
import Foundation
import Synchronization
import Testing

/// The player the app builds asks the server for the user's bitrate limit and picked version.
/// Each test plays with the versions picked in a store of its own (`MediaVersionChoices.current`),
/// so tests running side by side can't see or undo each other's choices.
@MainActor
struct PlaybackSettingsTests {
    private let suite = "PlaybackSettingsTests.\(UUID().uuidString)"
    private let choices: MediaVersionChoices

    init() throws {
        try #require(UserDefaults(suiteName: suite)).removePersistentDomain(forName: suite)
        choices = MediaVersionChoices(suiteName: suite)
    }

    @Test func `playback info carries the bitrate setting and the picked version`() async throws {
        let host = "settings.test"
        let userID = "settings-user-\(UUID().uuidString)"
        let server = PlaybackInfoServer.register(host: host)
        Preferences.maxBitrate.set(3_000_000)
        choices.choose("v1080", for: "m1", userID: userID)
        defer {
            Preferences.maxBitrate.reset()
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        let session = try JellyfinSession(
            serverURL: #require(URL(string: "https://\(host)/jf")),
            userID: userID,
            accessToken: "tok",
            identity: ClientIdentity(deviceName: "Test TV", deviceID: "device-1", appVersion: "0.1.0"),
            sessionConfiguration: { PlaybackInfoServer.sessionConfiguration() },
        )
        let playback = PlaybackController(
            session: session,
            request: PlaybackRequest(.item("m1")),
        )

        await MediaVersionChoices.$current.withValue(choices) {
            await playback.start()
        }
        await playback.stop()

        let body = try #require(server.bodies.first)
        #expect(body["MaxStreamingBitrate"] as? Int == 3_000_000)
        #expect(body["MediaSourceId"] as? String == "v1080")
    }

    @Test func `a picked version the server no longer has gives way to its first, from any queue`() async throws {
        let host = "goneversion.test"
        let userID = "settings-user-\(UUID().uuidString)"
        let server = PlaybackInfoServer.register(host: host)
        choices.choose("v720", for: "m1", userID: userID)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let session = try JellyfinSession(
            serverURL: #require(URL(string: "https://\(host)/jf")),
            userID: userID,
            accessToken: "tok",
            identity: ClientIdentity(deviceName: "Test TV", deviceID: "device-1", appVersion: "0.1.0"),
            sessionConfiguration: { PlaybackInfoServer.sessionConfiguration() },
        )
        // Played from Up Next, say, without the item's page loading first.
        let playback = PlaybackController(session: session, request: PlaybackRequest(.item("m1")))

        await MediaVersionChoices.$current.withValue(choices) {
            await playback.start()
        }
        await playback.stop()

        // The server answers without the version, as Jellyfin answers one it no longer has.
        #expect(server.bodies.map { $0["MediaSourceId"] as? String } == ["v720", nil])
        #expect(choices.choice(for: "m1", userID: userID) == nil)
    }

    @Test func `the limit is Wholphin's 100 Mbit/s until it's changed`() {
        #expect(Preferences.maxBitrate.defaultValue == 100_000_000)
        #expect(AVPlayerProfile.bitrateChoices.contains(Preferences.maxBitrate.defaultValue))
        #expect(AVPlayerProfile.bitrateChoices == AVPlayerProfile.bitrateChoices.sorted())
        #expect(AVPlayerProfile.bitrateChoices.first == 500_000)
        #expect(AVPlayerProfile.bitrateChoices.last == 200_000_000)
    }
}

/// A server that answers PlaybackInfo with nothing to play, recording what it was asked.
final class PlaybackInfoServer: URLProtocol {
    /// What each host was sent, as JSON data.
    private static let requests = Mutex<[String: [Data]]>([:])

    struct Recorder {
        let host: String

        var bodies: [[String: Any]] {
            let sent = PlaybackInfoServer.requests.withLock { $0[host] ?? [] }
            return sent.compactMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        }
    }

    static func register(host: String) -> Recorder {
        requests.withLock { $0[host] = [] }
        return Recorder(host: host)
    }

    static func sessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlaybackInfoServer.self]
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
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        else { return }
        let body = Self.body(of: request)
        Self.requests.withLock { $0[host, default: []].append(body) }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        // Nothing to play, so the player stops there.
        client?.urlProtocol(self, didLoad: Data(#"{"MediaSources":[]}"#.utf8))
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
