import AnemoneJellyfin
@testable import AnemonePlayback
import Foundation
import Synchronization
import Testing

/// The speed and MPV subtitle menus: what they show, and what choosing does.
@MainActor
struct MPVMenusTests {
    @Test func `the speed menu offers Wholphin's speeds and sets the engine's`() async throws {
        let engine = FakeEngine()
        let menu = PlaybackSpeedMenu()
        let controller = PlaybackController(
            request: PlaybackRequest(.item("a")),
            engine: engine,
            features: [menu],
            loadStream: FakeStreams().load,
        )

        await controller.start()
        #expect(await eventually { !controller.accessories.menus.isEmpty })
        let speeds = try #require(controller.accessories.menus.first { $0.id == "speed" })
        #expect(speeds.options.map(\.title) == ["0.25×", "0.5×", "0.75×", "Normal", "1.25×", "1.5×", "1.75×", "2×"])
        #expect(speeds.options.filter(\.isSelected).map(\.title) == ["Normal"])

        try #require(speeds.options.first { $0.title == "1.5×" }).select()

        #expect(engine.rate == 1.5)
        let updated = try #require(controller.accessories.menus.first { $0.id == "speed" })
        #expect(updated.options.filter(\.isSelected).map(\.title) == ["1.5×"])
        await controller.stop()
    }

    @Test func `subtitle menus show only while MPV plays`() async throws {
        let session = try StubServer.session(host: "menus-avplayer.test")
        let controller = PlaybackController(
            request: PlaybackRequest(.item("a")),
            engine: FakeEngine(),
            features: [MPVSubtitleMenus(session: session)],
            loadStream: FakeStreams().load,
        )

        await controller.start()
        try await Task.sleep(for: .milliseconds(20))

        #expect(controller.accessories.menus.isEmpty)
        await controller.stop()
    }

    @Test func `the delay steps by Wholphin's amounts and resets`() async throws {
        let client = FakeMPVClient()
        let controller = try mpvController(host: "menus-delay.test", client: client)

        await controller.start()
        #expect(await eventually { controller.accessories.menus.count == 2 })
        let delay = try #require(controller.accessories.menus.first { $0.id == "subtitleDelay" })
        #expect(delay.title == "Subtitle delay: 0 s")
        #expect(delay.options.map(\.title) == ["-1 s", "-0.25 s", "-0.05 s", "No delay", "+0.05 s", "+0.25 s", "+1 s"])
        #expect(delay.options.filter(\.isSelected).map(\.title) == ["No delay"])

        try option("+0.25 s", in: "subtitleDelay", controller).select()
        try option("+0.25 s", in: "subtitleDelay", controller).select()
        #expect(client.lastSet("sub-delay") == "0.5")
        #expect(try menu("subtitleDelay", controller).title == "Subtitle delay: +0.5 s")

        try option("-1 s", in: "subtitleDelay", controller).select()
        #expect(client.lastSet("sub-delay") == "-0.5")
        try option("No delay", in: "subtitleDelay", controller).select()
        #expect(client.lastSet("sub-delay") == "0.0")
        await controller.stop()
    }

    @Test func `searching lists what the server found, and downloading adds it to MPV`() async throws {
        let host = "menus-download.test"
        StubServer.answer(host: host) { request in
            switch (request.httpMethod, request.url?.path() ?? "") {
            case ("GET", "/jf/Items/a/RemoteSearch/Subtitles/eng"):
                #"[{"Id":"os-1","Name":"Movie.2026.srt","ProviderName":"OpenSubtitles","DownloadCount":12,"# +
                    #""IsHashMatch":true}]"#
            case ("POST", "/jf/Items/a/RemoteSearch/Subtitles/os-1"):
                ""
            case ("GET", "/jf/Items/a"):
                StubServer.item(withDownload: StubServer.downloaded(host))
            default:
                nil
            }
        }
        let client = FakeMPVClient()
        let controller = try mpvController(host: host, client: client)
        await controller.start()
        #expect(await eventually { controller.accessories.menus.count == 2 })
        #expect(try menu("subtitleSearch", controller).options.map(\.title) == ["Search in English"])

        try option("Search in English", in: "subtitleSearch", controller).select()
        #expect(await eventually { (try? menu("subtitleSearch", controller).options.count) == 2 })
        #expect(try menu("subtitleSearch", controller).options.first?.title
            == "Movie.2026.srt · Matches this file · OpenSubtitles · 12 downloads")

        try #require(menu("subtitleSearch", controller).options.first).select()
        #expect(await eventually { client.commands.last?.first == "sub-add" })
        let added = try #require(client.commands.last)
        #expect(added.count == 5)
        #expect(added[1].contains("/jf/Videos/a/src-a/Subtitles/3/Stream.srt"))
        #expect(added[1].contains("ApiKey=tok"))
        #expect(Array(added[2...]) == ["select", "English - SRT - External", "eng"])
        #expect(try menu("subtitleSearch", controller).title == "Showing English - SRT - External")
        await controller.stop()
    }

    @Test func `results describe what helps choose`() {
        let subtitle = RemoteSubtitle(
            id: "1",
            name: "Movie",
            provider: "Podnapisi",
            rating: 7.25,
            downloads: 3,
            isForced: true,
            isHearingImpaired: true,
            isMachineTranslated: true,
        )

        #expect(MPVSubtitleMenus.describe(subtitle)
            == "Movie · Podnapisi · ★ 7.2 · 3 downloads · Forced · SDH · Machine-translated")
        #expect(MPVSubtitleMenus.delayText(.milliseconds(-50)) == "-0.05 s")
        #expect(MPVSubtitleMenus.delayText(.seconds(1)) == "+1 s")
    }

    private func mpvController(host: String, client: FakeMPVClient) throws -> PlaybackController {
        let session = try StubServer.session(host: host)
        return PlaybackController(
            request: PlaybackRequest(.item("a")),
            engine: MPVPlayerEngine.testing(client),
            features: [MPVSubtitleMenus(session: session, languages: ["eng"], pollInterval: .milliseconds(1))],
            loadStream: FakeStreams().load,
        )
    }

    private func menu(_ id: String, _ controller: PlaybackController) throws -> PlayerMenu {
        try #require(controller.accessories.menus.first { $0.id == id })
    }

    private func option(_ title: String, in id: String, _ controller: PlaybackController) throws -> PlayerMenu.Option {
        try #require(menu(id, controller).options.first { $0.title == title })
    }
}

/// Answers a test's requests by host, as the Jellyfin tests' `MockServer` does.
final class StubServer: URLProtocol {
    typealias Answer = @Sendable (URLRequest) -> String?

    private static let answers = Mutex<[String: Answer]>([:])
    private static let downloads = Mutex<Set<String>>([])

    static func answer(host: String, with answer: @escaping Answer) {
        answers.withLock { $0[host] = answer }
    }

    /// Whether the test's server was asked to download subtitles.
    static func downloaded(_ host: String) -> Bool {
        downloads.withLock { $0.contains(host) }
    }

    static func session(host: String) throws -> JellyfinSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubServer.self]
        return try JellyfinSession(
            serverURL: #require(URL(string: "https://\(host)/jf")),
            userID: "u1",
            accessToken: "tok",
            identity: ClientIdentity(deviceName: "Test TV", deviceID: "device-1", appVersion: "0.1.0"),
            sessionConfiguration: { configuration },
        )
    }

    /// Item `a` with version `src-a`, and once downloaded, an external English SRT.
    static func item(withDownload: Bool) -> String {
        let download = withDownload
            ? #",{"Index":3,"Type":"Subtitle","Codec":"srt","Language":"eng","IsExternal":true,"# +
            #""Path":"/media/a.en.srt","DisplayTitle":"English - SRT - External"}"#
            : ""
        return #"{"Id":"a","Name":"A","Type":"Movie","MediaSources":[{"Id":"src-a","MediaStreams":["# +
            #"{"Index":0,"Type":"Video"},{"Index":2,"Type":"Subtitle","Codec":"ass"}\#(download)]}]}"#
    }

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url, let host = url.host(),
              let answer = Self.answers.withLock({ $0[host] }),
              let body = answer(request),
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        if request.httpMethod == "POST" {
            Self.downloads.withLock { _ = $0.insert(host) }
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
