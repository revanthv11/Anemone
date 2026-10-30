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

    @Test func `a special next up between seasons plays, then the regular episodes, as in Wholphin`() async throws {
        _ = register(host: "queue-placed.test", replies: [
            "/Shows/NextUp": Self.items([Self.episode("sp1", season: 0, number: 1)]),
            // The server places the specials before season 2.
            "/Shows/s1/Episodes": Self.items([
                Self.episode("sp1", season: 0, number: 1),
                Self.episode("sp2", season: 0, number: 2),
                Self.episode("e4", season: 2, number: 1),
                Self.episode("e5", season: 2, number: 2),
            ]),
        ])

        let queue = try await session(host: "queue-placed.test").seriesQueue(seriesID: "s1")

        #expect(queue.map(\.id) == ["sp1", "e4", "e5"])
    }

    @Test func `a special next up after the last season plays from there, as in Wholphin`() async throws {
        let sent = register(host: "queue-last.test", replies: [
            "/Shows/NextUp": Self.items([Self.episode("sp1", season: 0, number: 1)]),
            // The server lists the series from the special on: it and the one after it.
            "/Shows/s1/Episodes": Self.items([
                Self.episode("sp1", season: 0, number: 1),
                Self.episode("sp2", season: 0, number: 2),
            ]),
        ])

        let queue = try await session(host: "queue-last.test").seriesQueue(seriesID: "s1")

        // Not the series again from its first episode.
        #expect(queue.map(\.id) == ["sp1", "sp2"])
        #expect(sent["/Shows/s1/Episodes"]?.query["startItemId"] == "sp1")
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

    @Test func `a video split across files is followed by its other parts`() async throws {
        let sent = register(host: "queue-parts.test", replies: [
            "/Videos/m1/AdditionalParts": Self.items([Self.movie("m1b"), Self.movie("m1c")]),
        ])
        let session = try session(host: "queue-parts.test")
        let split = ItemDetails(item: MediaItem(id: "m1", name: "Film", kind: .movie, partCount: 3))
        let whole = ItemDetails(item: MediaItem(id: "m2", name: "Other", kind: .movie))

        let parts = try await session.additionalParts(of: split)
        let queue = await session.addingParts(to: [whole, split])

        #expect(parts.map(\.id) == ["m1b", "m1c"])
        #expect(queue.map(\.id) == ["m2", "m1", "m1b", "m1c"])
        #expect(sent["/Videos/m1/AdditionalParts"]?.query["userId"] == "u1")
        #expect(sent["/Videos/m2/AdditionalParts"] == nil)
    }

    @Test func `the server's part count comes with a queue's items, one file counting as none`() async throws {
        let sent = register(host: "queue-partcount.test", replies: [
            "/Shows/s1/Episodes": Self.items([
                Self.episode("e1", season: 1, number: 1, partCount: 2),
                Self.episode("e2", season: 1, number: 2, partCount: 1),
            ]),
            "/Videos/e1/AdditionalParts": Self.items([Self.episode("e1b", season: 1, number: 1)]),
        ])
        let session = try session(host: "queue-partcount.test")

        let episodes = try await session.seasonQueue(seriesID: "s1", seasonID: "season1")
        let queue = await session.addingParts(to: episodes)

        #expect(episodes.map(\.item.partCount) == [2, nil])
        #expect(queue.map(\.id) == ["e1", "e1b", "e2"])
        #expect(sent["/Videos/e2/AdditionalParts"] == nil)
    }

    @Test func `a video whose parts can't be read plays alone, and the rest keep theirs`() async throws {
        // No reply for m1's parts, so that request fails.
        _ = register(host: "queue-partsfail.test", replies: [
            "/Videos/m2/AdditionalParts": Self.items([Self.movie("m2b")]),
        ])
        let session = try session(host: "queue-partsfail.test")
        let broken = ItemDetails(item: MediaItem(id: "m1", name: "Broken", kind: .movie, partCount: 2))
        let whole = ItemDetails(item: MediaItem(id: "m3", name: "Whole", kind: .movie))
        let split = ItemDetails(item: MediaItem(id: "m2", name: "Split", kind: .movie, partCount: 2))

        let queue = await session.addingParts(to: [broken, whole, split])

        #expect(queue.map(\.id) == ["m1", "m3", "m2", "m2b"])
    }

    @Test func `a queue starts at the entry picked, its own copy of a repeated item`() throws {
        let film = ItemDetails(item: MediaItem(id: "m1", name: "Film", kind: .movie))
        let other = ItemDetails(item: MediaItem(id: "m2", name: "Other", kind: .movie))
        let song = ItemDetails(item: MediaItem(id: "a1", name: "Song", kind: .audio))
        // The page lists Film, Song, Other, Film; the queue holds its videos only.
        let listed = [film, song, other, film]
        let videos = [film, other, film]

        let second = try #require(QueueStart(at: 3, in: listed))
        let fromSong = try #require(QueueStart(at: 1, in: listed))

        #expect(second.index(in: videos) == 2)
        #expect(fromSong.itemID == "m2")
        #expect(fromSong.index(in: videos) == 1)
        #expect(QueueStart(at: 0, in: listed)?.index(in: videos) == 0)
        // A copy the queue no longer has, and a song with no video after it.
        #expect(second.index(in: [film, other]) == nil)
        #expect(QueueStart(at: 1, in: [film, song]) == nil)
    }

    static func movie(_ id: String) -> String {
        #"{"Id":"\#(id)","Name":"Film \#(id)","Type":"Movie","LocationType":"FileSystem"}"#
    }

    static func items(_ items: [String]) -> String {
        #"{"Items":[\#(items.joined(separator: ","))],"TotalRecordCount":\#(items.count)}"#
    }

    static func episode(
        _ id: String,
        season: Int,
        number: Int,
        resumeTicks: Int = 0,
        location: String = "FileSystem",
        partCount: Int? = nil,
    ) -> String {
        let parts = partCount.map { #","PartCount":\#($0)"# } ?? ""
        return #"""
        {"Id":"\#(id)","Name":"Episode \#(id)","Type":"Episode","SeriesId":"s1","SeriesName":"Show",
         "ParentIndexNumber":\#(season),"IndexNumber":\#(number),"LocationType":"\#(location)"\#(parts),
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
