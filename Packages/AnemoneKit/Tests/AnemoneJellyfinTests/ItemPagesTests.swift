import AnemoneJellyfin
import Foundation
import Synchronization
import Testing

/// Item-page queries against the fake server: what's asked for, and how answers are mapped.
struct ItemPagesTests {
    private func session(host: String) throws -> JellyfinSession {
        try JellyfinSession(
            serverURL: #require(URL(string: "https://\(host)")),
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

    @Test func `maps a movie's full details`() async throws {
        let sent = register(host: "movie.test", path: "/Items/m1", reply: .json(Self.movieJSON))

        let movie = try await session(host: "movie.test").itemDetails(id: "m1")

        #expect(sent.last.withLock { $0?.query["userId"] } == "u1")
        #expect(movie.item.name == "Film")
        #expect(movie.item.kind == .movie)
        #expect(movie.tagline == "One last job.")
        #expect(movie.genres == ["Drama", "Thriller"])
        #expect(movie.studios == ["Studio A"])
        #expect(movie.communityRating == 7.5)
        #expect(movie.criticRating == 91)
        #expect(movie.logo == ItemImage(itemID: "m1", kind: .logo, tag: "logo"))
        #expect(movie.userState == .init(isPlayed: false, isFavorite: true, resumePosition: .seconds(1800)))
        #expect(movie.timeRemaining == .seconds(5400))
        #expect(movie.directors == ["Dee Rector"])
    }

    @Test func `credits keep characters for actors and jobs for crew`() async throws {
        _ = register(host: "people.test", path: "/Items/m1", reply: .json(Self.movieJSON))

        let people = try await session(host: "people.test").itemDetails(id: "m1").people

        #expect(people.map(\.name) == ["Ann Actor", "Dee Rector", "Wri Ter", "Pro Ducer", "Com Poser"])
        #expect(people.map(\.role) == ["Max", "Director", "Screenplay - Writer", "Executive Producer", "Composer"])
        #expect(people.map(\.kind) == [.actor, .director, .writer, .producer, .composer])
        #expect(people.first?.image == ItemImage(itemID: "p1", kind: .primary, tag: "face"))
        #expect(people.last?.image == nil)
        // The second "Ann Actor as Max" is the same credit twice, so it's dropped.
        #expect(people.first?.person == MediaItem(
            id: "p1",
            name: "Ann Actor",
            kind: .person,
            artwork: .init(primaryTag: "face"),
        ))
    }

    @Test func `an episode shows its series' logo`() async throws {
        _ = register(host: "episode.test", path: "/Items/e1", reply: .json(#"""
        {"Id":"e1","Name":"Pilot","Type":"Episode","SeriesId":"s1","SeriesName":"Show","SeasonId":"season1",
         "ParentIndexNumber":1,"IndexNumber":3,"ImageTags":{"Primary":"still","Logo":"own"},
         "ParentLogoItemId":"s1","ParentLogoImageTag":"serieslogo"}
        """#))

        let episode = try await session(host: "episode.test").itemDetails(id: "e1")

        #expect(episode.logo == ItemImage(itemID: "s1", kind: .logo, tag: "serieslogo"))
        #expect(episode.seasonID == "season1")
        #expect(episode.indexNumber == 3)
        #expect(episode.ownPrimaryImage == ItemImage(itemID: "e1", kind: .primary, tag: "still"))
    }

    @Test func `loads a series' seasons in order`() async throws {
        let sent = register(host: "seasons.test", path: "/Items", reply: .items(
            #"{"Id":"sn1","Name":"Season 1","Type":"Season","IndexNumber":1,"SeriesId":"s1","ChildCount":10,"#
                + #""UserData":{"Key":"sn1","Played":true,"UnplayedItemCount":0}}"#,
            #"{"Id":"sn2","Name":"Season 2","Type":"Season","IndexNumber":2,"SeriesId":"s1","ChildCount":8,"#
                + #""UserData":{"Key":"sn2","Played":false,"UnplayedItemCount":5}}"#,
        ))

        let seasons = try await session(host: "seasons.test").seasons(ofSeries: "s1")

        #expect(seasons.map(\.id) == ["sn1", "sn2"])
        #expect(seasons.map(\.indexNumber) == [1, 2])
        #expect(seasons.map(\.childCount) == [10, 8])
        #expect(seasons.map(\.userState.unplayedCount) == [0, 5])
        #expect(seasons.first?.item.episode?.seriesID == "s1")
        let query = try #require(sent.last.withLock { $0 }).query
        #expect(query["parentId"] == "s1")
        #expect(query["includeItemTypes"] == "Season")
        #expect(query["sortBy"] == "IndexNumber")
        #expect(query["recursive"] == "false")
        #expect(query["userId"] == "u1")
    }

    @Test func `loads a season's episodes with their people`() async throws {
        let sent = register(host: "episodes.test", path: "/Shows/s1/Episodes", reply: .items(
            #"{"Id":"e1","Name":"Pilot","Type":"Episode","SeriesId":"s1","SeasonId":"sn1","#
                + #""ParentIndexNumber":1,"IndexNumber":1,"Overview":"It begins.","#
                + #""People":[{"Id":"g1","Name":"Gus Guest","Role":"Bob","Type":"GuestStar"}],"#
                + #""UserData":{"Key":"e1","Played":true}}"#,
            #"{"Id":"e2","Name":"Second","Type":"Episode","SeriesId":"s1","SeasonId":"sn1","#
                + #""ParentIndexNumber":1,"IndexNumber":2,"UserData":{"Key":"e2","PlaybackPositionTicks":600000000}}"#,
        ))

        let episodes = try await session(host: "episodes.test").episodes(ofSeries: "s1", season: "sn1")

        #expect(episodes.map(\.id) == ["e1", "e2"])
        #expect(episodes.first?.people == [
            Credit(personID: "g1", name: "Gus Guest", kind: .guestStar, role: "Bob"),
        ])
        #expect(episodes.first?.item.overview == "It begins.")
        #expect(episodes.map(\.userState.isPlayed) == [true, false])
        #expect(episodes.last?.userState.resumePosition == .seconds(60))
        let query = try #require(sent.last.withLock { $0 }).query
        #expect(query["seasonId"] == "sn1")
        #expect(query["sortBy"] == "IndexNumber")
        #expect(query["fields"]?.contains("People") == true)
    }

    @Test func `asks for up to 25 similar items`() async throws {
        let sent = register(host: "similar.test", path: "/Items/m1/Similar", reply: .items(
            #"{"Id":"m2","Name":"Other Film","Type":"Movie"}"#,
        ))

        let similar = try await session(host: "similar.test").similarItems(to: "m1")

        #expect(similar.map(\.id) == ["m2"])
        #expect(sent.last.withLock { $0?.query["limit"] } == "25")
    }

    @Test func `splits a collection into rows by type in Wholphin's order`() async throws {
        let sent = register(host: "boxset.test", path: "/Items", reply: .items(
            #"{"Id":"ep","Name":"Special","Type":"Episode"}"#,
            #"{"Id":"m1","Name":"First","Type":"Movie"}"#,
            #"{"Id":"p","Name":"Someone","Type":"Person"}"#,
            #"{"Id":"s1","Name":"Show","Type":"Series"}"#,
            #"{"Id":"m2","Name":"Second","Type":"Movie"}"#,
            #"{"Id":"inner","Name":"Inner Collection","Type":"BoxSet","ChildCount":2}"#,
        ))

        let items = try await session(host: "boxset.test").collectionItems(
            id: "c1",
            sort: LibrarySort(.default),
            filter: LibraryFilter(),
        )
        let sections = CollectionSection.sections(items)

        #expect(sections.map(\.kind) == [.movie, .series, .episode, .collection])
        #expect(sections.first?.items.map(\.id) == ["m1", "m2"])
        #expect(sections.last?.items.first?.childCount == 2)
        let query = try #require(sent.last.withLock { $0 }).query
        #expect(query["parentId"] == "c1")
        #expect(query["recursive"] == "false")
        #expect(query["sortBy"] == "Default")
        #expect(query["includeItemTypes"] == nil)
    }

    @Test func `loads a playlist in its own order`() async throws {
        let sent = register(host: "playlist.test", path: "/Playlists/pl1/Items", reply: .items(
            #"{"Id":"e9","Name":"Late Episode","Type":"Episode","SeriesName":"Show","RunTimeTicks":13200000000}"#,
            #"{"Id":"m1","Name":"Film","Type":"Movie"}"#,
        ))

        let items = try await session(host: "playlist.test").playlistItems(id: "pl1")

        #expect(items.map(\.id) == ["e9", "m1"])
        #expect(items.first?.item.runtime == .seconds(1320))
        #expect(sent.last.withLock { $0?.query["userId"] } == "u1")
    }

    @Test func `loads a person's movies newest first`() async throws {
        let sent = register(host: "person.test", path: "/Items", reply: .items(
            #"{"Id":"m3","Name":"Newest","Type":"Movie","ProductionYear":2025}"#,
            #"{"Id":"m1","Name":"Oldest","Type":"Movie","ProductionYear":1999}"#,
        ))

        let movies = try await session(host: "person.test").filmography(ofPerson: "p1", row: .movies)

        #expect(movies.map(\.id) == ["m3", "m1"])
        let query = try #require(sent.last.withLock { $0 }).query
        #expect(query["personIds"] == "p1")
        #expect(query["includeItemTypes"] == "Movie")
        #expect(query["recursive"] == "true")
        #expect(query["sortBy"] == "PremiereDate,ProductionYear,SortName")
        #expect(query["sortOrder"] == "Descending,Descending,Ascending")
    }

    @Test func `marks items played and unplayed`() async throws {
        let sent = register(
            host: "played.test",
            path: "/UserPlayedItems/e1",
            reply: .json(#"{"Key":"e1","Played":true,"IsFavorite":false,"PlaybackPositionTicks":0}"#),
        )

        let state = try await session(host: "played.test").setPlayed(true, itemID: "e1")

        #expect(state == .init(isPlayed: true))
        #expect(sent.last.withLock { $0?.method } == "POST")
        #expect(sent.last.withLock { $0?.query["userId"] } == "u1")

        try await session(host: "played.test").setPlayed(false, itemID: "e1")

        #expect(sent.last.withLock { $0?.method } == "DELETE")
    }

    @Test func `adds and removes favourites`() async throws {
        let sent = register(
            host: "favorite.test",
            path: "/UserFavoriteItems/p1",
            reply: .json(#"{"Key":"p1","IsFavorite":true}"#),
        )

        let state = try await session(host: "favorite.test").setFavorite(true, itemID: "p1")

        #expect(state.isFavorite)
        #expect(sent.last.withLock { $0?.method } == "POST")

        try await session(host: "favorite.test").setFavorite(false, itemID: "p1")

        #expect(sent.last.withLock { $0?.method } == "DELETE")
    }

    @Test func `asks whether the user may edit a playlist`() async throws {
        let sent = register(
            host: "playlist-user.test",
            path: "/Playlists/pl1/Users/u1",
            reply: .json(#"{"UserId":"u1","CanEdit":true}"#),
        )

        #expect(try await session(host: "playlist-user.test").canEditPlaylist(id: "pl1"))
        #expect(sent.last.withLock { $0?.method } == "GET")
    }

    @Test func `a playlist the user has no say over can't be edited`() async throws {
        MockServer.register(host: "playlist-other.test") { _ in MockServer.Reply(status: 404, body: "") }
        MockServer.register(host: "playlist-revoked.test") { _ in .unauthorized }

        #expect(try await !session(host: "playlist-other.test").canEditPlaylist(id: "pl1"))
        await #expect(throws: SessionError.signedOut) {
            try await session(host: "playlist-revoked.test").canEditPlaylist(id: "pl1")
        }
    }

    @Test func `moves a playlist entry`() async throws {
        let sent = register(
            host: "playlist-move.test",
            path: "/Playlists/pl1/Items/m1/Move/0",
            reply: MockServer.Reply(status: 204, body: ""),
        )

        try await session(host: "playlist-move.test").movePlaylistItem("m1", inPlaylist: "pl1", to: 0)

        #expect(sent.last.withLock { $0?.method } == "POST")
    }

    @Test func `item details report a revoked token as signed out`() async throws {
        MockServer.register(host: "revoked-details.test") { _ in .unauthorized }

        await #expect(throws: SessionError.signedOut) {
            try await session(host: "revoked-details.test").itemDetails(id: "m1")
        }
    }

    // MARK: Fixtures

    private static let movieJSON = #"""
    {"Id":"m1","Name":"Film","Type":"Movie","ProductionYear":2024,"RunTimeTicks":72000000000,
     "Taglines":["","One last job."],"Genres":["Drama","Thriller"],
     "Studios":[{"Name":"Studio A","Id":"st1"}],"CommunityRating":7.5,"CriticRating":91,
     "ImageTags":{"Primary":"p","Logo":"logo"},
     "UserData":{"Key":"m1","IsFavorite":true,"Played":false,"PlaybackPositionTicks":18000000000},
     "People":[
       {"Id":"p1","Name":"Ann Actor","Role":"Max","Type":"Actor","PrimaryImageTag":"face"},
       {"Id":"p1","Name":"Ann Actor","Role":"Max","Type":"Actor","PrimaryImageTag":"face"},
       {"Id":"p2","Name":"Dee Rector","Role":"Director","Type":"Director"},
       {"Id":"p3","Name":"Wri Ter","Role":"Screenplay","Type":"Writer"},
       {"Id":"p4","Name":"Pro Ducer","Role":"Executive Producer","Type":"Producer"},
       {"Id":"p5","Name":"Com Poser","Type":"Composer"}
     ]}
    """#
}

private extension MockServer.Reply {
    static func items(_ items: String...) -> Self {
        .json(#"{"Items":[\#(items.joined(separator: ","))]}"#)
    }
}
