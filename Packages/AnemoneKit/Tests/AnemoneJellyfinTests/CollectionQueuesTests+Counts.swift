import AnemoneJellyfin
import Foundation
import Testing

/// What a collection's queue leaves out, and how the server is asked to count it.
extension CollectionQueuesTests {
    @Test func `a series cut short by episodes already queued is asked for again from where it ended`() async throws {
        // e1 on its own, then 97 movies, leave room for 2 of the series' 4 episodes: e1 again and e2.
        let movies = (1 ... 97).map { Self.movie("m\($0)") }
        let episodes = ["e1", "e2", "e3", "e4"].map(Self.episode)
        let recorder = register(host: "collection-series-again.test") { request in
            guard request.query["limit"] != "0" else { return #"{"Items":[],"TotalRecordCount":101}"# }
            switch request.query["parentId"] {
            case "c1":
                return Self.items([Self.episode("e1")] + movies + [Self.series("s1")])
            case "s1":
                let start = request.query["startIndex"].flatMap { Int($0) } ?? 0
                let limit = request.query["limit"].flatMap { Int($0) } ?? episodes.count
                return Self.items(Array(episodes.dropFirst(start).prefix(limit)))
            default:
                return nil
            }
        }

        let found = try await session(host: "collection-series-again.test").collectionQueue(id: "c1", shuffled: false)

        // Before, the series stopped at e2, with 99 queued and nothing counted.
        #expect(found.items.count == 100)
        #expect(found.items.suffix(2).map(\.id) == ["e2", "e3"])
        #expect(found.overLimitCount == 1)
        #expect(found.skippedCount == 0)
        let asked = recorder.requests.filter { $0.query["parentId"] == "s1" }
        #expect(asked.map { $0.query["startIndex"] } == [nil, "2"])
        #expect(asked.map { $0.query["limit"] } == ["2", "1"])
    }

    @Test(.timeLimit(.minutes(1)))
    func `a server that ignores where to start isn't asked for the same episodes again and again`() async throws {
        // As above, but the series' first episodes come back wherever they're asked to start.
        let movies = (1 ... 97).map { Self.movie("m\($0)") }
        let episodes = ["e1", "e2", "e3", "e4"].map(Self.episode)
        let recorder = register(host: "collection-series-ignores-start.test") { request in
            guard request.query["limit"] != "0" else { return #"{"Items":[],"TotalRecordCount":101}"# }
            switch request.query["parentId"] {
            case "c1":
                return Self.items([Self.episode("e1")] + movies + [Self.series("s1")])
            case "s1":
                let limit = request.query["limit"].flatMap { Int($0) } ?? episodes.count
                return Self.items(Array(episodes.prefix(limit)))
            default:
                return nil
            }
        }

        let session = try session(host: "collection-series-ignores-start.test")
        let found = try await session.collectionQueue(id: "c1", shuffled: false)

        // Before, e1 was asked for again and again, for ever.
        #expect(found.items.count == 99)
        #expect(found.items.last?.id == "e2")
        let asked = recorder.requests.filter { $0.query["parentId"] == "s1" }
        #expect(asked.map { $0.query["startIndex"] } == [nil, "2"])
    }

    @Test func `play and shuffle count each song of an album in a collection`() async throws {
        let host = "collection-album.test"
        _ = register(host: host) { request in
            if request.query["limit"] == "0" {
                // m1 and the album's three songs.
                let count = request.query["includeItemTypes"] == Self.videoTypes ? 1 : 4
                return #"{"Items":[],"TotalRecordCount":\#(count)}"#
            }
            if request.query["sortBy"] == "Random" {
                return #"{"Items":[\#(Self.movie("m1"))],"TotalRecordCount":1}"#
            }
            return request.query["parentId"] == "c1" ? Self.items([Self.movie("m1"), Self.album("al1")]) : nil
        }

        let played = try await session(host: host).collectionQueue(id: "c1", shuffled: false)
        let shuffled = try await session(host: host).collectionQueue(id: "c1", shuffled: true)

        #expect(played.items.map(\.id) == ["m1"])
        // Before, Play counted the album as 1.
        #expect(played.skippedCount == 3)
        #expect(shuffled.skippedCount == 3)
    }

    @Test func `a collection too deep inside to go into is counted as left out`() async throws {
        let recorder = register(host: "collection-deep.test") { request in
            // m4, and m5 in the collection too deep.
            guard request.query["limit"] != "0" else { return #"{"Items":[],"TotalRecordCount":2}"# }
            return switch request.query["parentId"] {
            case "c1": Self.items([Self.boxSet("b1")])
            case "b1": Self.items([Self.boxSet("b2")])
            case "b2": Self.items([Self.boxSet("b3")])
            case "b3": Self.items([Self.boxSet("b4")])
            case "b4": Self.items([Self.boxSet("b5"), Self.movie("m4")])
            case "b5": Self.items([Self.movie("m5")])
            default: nil
            }
        }

        let found = try await session(host: "collection-deep.test").collectionQueue(id: "c1", shuffled: false)

        #expect(found.items.map(\.id) == ["m4"])
        // Before, it was passed over without a word.
        #expect(found.skippedCount == 1)
        #expect(!recorder.requests.contains { $0.query["parentId"] == "b5" })
    }

    @Test func `a full queue's two counts are asked for together`() async throws {
        let host = "collection-counts-together.test"
        let movies = (1 ... 100).map { Self.movie("m\($0)") }
        PairedRequests.register(
            host: host,
            isPaired: { $0.query["limit"] == "0" },
            reply: { request in
                guard request.query["limit"] == "0" else { return .json(Self.items(movies)) }
                let count = request.query["includeItemTypes"] == Self.videoTypes ? 104 : 106
                return .json(#"{"Items":[],"TotalRecordCount":\#(count)}"#)
            },
        )

        let found = try await pairedSession(host: host).collectionQueue(id: "c1", shuffled: false)

        #expect(found.items.count == 100)
        #expect(found.overLimitCount == 4)
        #expect(found.skippedCount == 2)
        #expect(PairedRequests.wereTogether(host: host))
    }

    @Test func `shuffled, the videos and the count are asked for together`() async throws {
        let host = "collection-shuffle-together.test"
        PairedRequests.register(
            host: host,
            isPaired: { _ in true },
            reply: { request in
                request.query["limit"] == "0"
                    ? .json(#"{"Items":[],"TotalRecordCount":3}"#)
                    : .json(#"{"Items":[\#(Self.movie("m1"))],"TotalRecordCount":1}"#)
            },
        )

        let found = try await pairedSession(host: host).collectionQueue(id: "c1", shuffled: true)

        #expect(found.items.map(\.id) == ["m1"])
        #expect(found.skippedCount == 2)
        #expect(PairedRequests.wereTogether(host: host))
    }

    private func pairedSession(host: String) throws -> JellyfinSession {
        try JellyfinSession(
            serverURL: #require(URL(string: "https://\(host)")),
            userID: "u1",
            accessToken: "tok",
            identity: ClientIdentity(deviceName: "Test TV", deviceID: "device-1", appVersion: "0.1.0"),
            sessionConfiguration: { PairedRequests.sessionConfiguration() },
        )
    }
}
