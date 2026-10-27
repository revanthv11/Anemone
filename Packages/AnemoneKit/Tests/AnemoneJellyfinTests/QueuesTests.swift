import AnemoneJellyfin
import Foundation
import Synchronization
import Testing

/// What Play and Shuffle ask the server for, and what they make of the answers.
struct QueuesTests {
    private func session(host: String) throws -> JellyfinSession {
        try JellyfinSession(
            serverURL: #require(URL(string: "https://\(host)")),
            userID: "u1",
            accessToken: "tok",
            identity: ClientIdentity(deviceName: "Test TV", deviceID: "device-1", appVersion: "0.1.0"),
            sessionConfiguration: { MockServer.sessionConfiguration() },
        )
    }

    /// Answers each path with its reply, recording the requests by path.
    private func register(host: String, replies: [String: String]) -> Requests {
        let requests = Requests()
        MockServer.register(host: host) { request in
            guard let path = request.url?.path(), let body = replies[path] else { return nil }
            requests.sent.withLock { $0[path] = SentRequest(request) }
            return .json(body)
        }
        return requests
    }

    @Test func `series play starts at the episode next up and leaves out specials`() async throws {
        let sent = register(host: "queue-series.test", replies: [
            "/Shows/NextUp": Self.items([Self.episode("e3", season: 1, number: 3, resumeTicks: 600_000_000)]),
            "/Shows/s1/Episodes": Self.items([
                Self.episode("e3", season: 1, number: 3, resumeTicks: 600_000_000),
                Self.episode("e4", season: 1, number: 4),
                Self.episode("sp1", season: 0, number: 1),
                Self.episode("e5", season: 2, number: 1),
                Self.episode("e6", season: 2, number: 2, location: "Virtual"),
            ]),
        ])

        let queue = try await session(host: "queue-series.test").seriesQueue(seriesID: "s1")

        #expect(queue.map(\.id) == ["e3", "e4", "e5"])
        #expect(queue.first?.userState.resumePosition == .seconds(60))
        let nextUp = try #require(sent["/Shows/NextUp"])
        #expect(nextUp.query["seriesId"] == "s1")
        #expect(nextUp.query["userId"] == "u1")
        #expect(nextUp.query["limit"] == "1")
        let episodes = try #require(sent["/Shows/s1/Episodes"])
        #expect(episodes.query["startItemId"] == "e3")
        #expect(episodes.query["limit"] == "100")
        #expect(episodes.query["fields"] == "Overview")
        #expect(episodes.query["seasonId"] == nil)
        #expect(episodes.query["sortBy"] == nil)
    }

    @Test func `with nothing next up, series play starts at the first regular episode`() async throws {
        let sent = register(host: "queue-rewatch.test", replies: [
            "/Shows/NextUp": Self.items([]),
            "/Shows/s1/Episodes": Self.items([
                Self.episode("sp1", season: 0, number: 1),
                Self.episode("e1", season: 1, number: 1),
                Self.episode("e2", season: 1, number: 2),
            ]),
        ])

        let queue = try await session(host: "queue-rewatch.test").seriesQueue(seriesID: "s1")

        #expect(queue.map(\.id) == ["e1", "e2"])
        #expect(sent["/Shows/s1/Episodes"]?.query["startItemId"] == nil)
    }

    @Test func `a series of specials alone still plays`() async throws {
        _ = register(host: "queue-specials.test", replies: [
            "/Shows/s1/Episodes": Self.items([Self.episode("sp1", season: 0, number: 1)]),
        ])

        let queue = try await session(host: "queue-specials.test").episodes(ofSeries: "s1", from: nil)

        #expect(queue.map(\.id) == ["sp1"])
    }

    @Test func `playing on from a special keeps to the specials`() async throws {
        _ = register(host: "queue-special.test", replies: [
            "/Shows/s1/Episodes": Self.items([
                Self.episode("sp1", season: 0, number: 1),
                Self.episode("sp2", season: 0, number: 2),
                Self.episode("e1", season: 1, number: 1),
            ]),
        ])

        let queue = try await session(host: "queue-special.test").episodes(ofSeries: "s1", from: "sp1")

        #expect(queue.map(\.id) == ["sp1", "sp2"])
    }

    @Test func `shuffle asks the server for random episodes of the series or the season`() async throws {
        let sent = register(host: "queue-shuffle.test", replies: [
            "/Shows/s1/Episodes": Self.items([
                Self.episode("e2", season: 1, number: 2),
                Self.episode("sp1", season: 0, number: 1),
            ]),
        ])
        let session = try session(host: "queue-shuffle.test")

        let series = try await session.shuffledEpisodes(ofSeries: "s1")
        #expect(series.map(\.id) == ["e2", "sp1"])
        let seriesRequest = try #require(sent["/Shows/s1/Episodes"])
        #expect(seriesRequest.query["sortBy"] == "Random")
        #expect(seriesRequest.query["limit"] == "100")
        #expect(seriesRequest.query["seasonId"] == nil)

        _ = try await session.shuffledEpisodes(ofSeries: "s1", season: "season1")
        #expect(sent["/Shows/s1/Episodes"]?.query["seasonId"] == "season1")
        #expect(sent["/Shows/s1/Episodes"]?.query["sortBy"] == "Random")
    }

    @Test func `season play is the season's episodes in order`() async throws {
        let sent = register(host: "queue-season.test", replies: [
            "/Shows/s1/Episodes": Self.items([
                Self.episode("e1", season: 1, number: 1),
                Self.episode("e2", season: 1, number: 2),
            ]),
        ])

        let queue = try await session(host: "queue-season.test").seasonQueue(seriesID: "s1", seasonID: "season1")

        #expect(queue.map(\.id) == ["e1", "e2"])
        let request = try #require(sent["/Shows/s1/Episodes"])
        #expect(request.query["seasonId"] == "season1")
        #expect(request.query["sortBy"] == nil)
    }

    @Test func `a collection plays its videos in its own order and counts the rest`() async throws {
        let sent = register(host: "queue-collection.test", replies: [
            "/Items": Self.items([
                #"{"Id":"m1","Name":"Film","Type":"Movie"}"#,
                Self.episode("e1", season: 1, number: 1),
                #"{"Id":"a1","Name":"Song","Type":"Audio"}"#,
            ]),
        ])
        let session = try session(host: "queue-collection.test")

        let found = try await session.collectionQueue(id: "c1", shuffled: false)

        #expect(found.items.map(\.id) == ["m1", "e1"])
        #expect(found.skippedCount == 1)
        let request = try #require(sent["/Items"])
        #expect(request.query["parentId"] == "c1")
        #expect(request.query["recursive"] == "true")
        #expect(request.query["filters"] == "IsNotFolder")
        #expect(request.query["excludeItemIds"] == "c1")
        #expect(request.query["excludeLocationTypes"] == "Virtual")
        #expect(request.query["sortBy"] == "Default")
        #expect(request.query["limit"] == "100")

        _ = try await session.collectionQueue(id: "c1", shuffled: true)
        #expect(sent["/Items"]?.query["sortBy"] == "Random")
    }

    @Test func `a playlist plays its videos in the playlist's order and counts the rest`() async throws {
        let sent = register(host: "queue-playlist.test", replies: [
            "/Playlists/p1/Items": Self.items([
                #"{"Id":"m1","Name":"Film","Type":"Movie"}"#,
                #"{"Id":"a1","Name":"Song","Type":"Audio"}"#,
                #"{"Id":"ph1","Name":"Beach","Type":"Photo"}"#,
                #"{"Id":"mv1","Name":"Clip","Type":"MusicVideo"}"#,
            ]),
        ])

        let found = try await session(host: "queue-playlist.test").playlistQueue(id: "p1")

        #expect(found.items.map(\.id) == ["m1", "mv1"])
        #expect(found.skippedCount == 2)
        let request = try #require(sent["/Playlists/p1/Items"])
        #expect(request.query["userId"] == "u1")
        #expect(request.query["fields"] == "Overview")
        #expect(request.query["limit"] == nil)
    }

    private static func items(_ items: [String]) -> String {
        #"{"Items":[\#(items.joined(separator: ","))],"TotalRecordCount":\#(items.count)}"#
    }

    private static func episode(
        _ id: String,
        season: Int,
        number: Int,
        resumeTicks: Int = 0,
        location: String = "FileSystem",
    ) -> String {
        #"""
        {"Id":"\#(id)","Name":"Episode \#(id)","Type":"Episode","SeriesId":"s1","SeriesName":"Show",
         "ParentIndexNumber":\#(season),"IndexNumber":\#(number),"LocationType":"\#(location)",
         "UserData":{"Key":"\#(id)","PlaybackPositionTicks":\#(resumeTicks),"Played":false}}
        """#
    }
}

/// The last request a fake server saw on each path.
private final class Requests: Sendable {
    let sent = Mutex<[String: SentRequest]>([:])

    subscript(path: String) -> SentRequest? {
        sent.withLock { $0[path] }
    }
}
