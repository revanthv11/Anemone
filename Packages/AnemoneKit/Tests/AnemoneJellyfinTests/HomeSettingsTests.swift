import AnemoneCore
@testable import AnemoneJellyfin
import Foundation
import Synchronization
import Testing

/// Keeping home settings on the server, the companion plugin, and Next Up removals.
struct HomeSettingsTests {
    private static let savedJSON = #"{"version":1,"rows":[{"type":"NextUp"},{"type":"Genres","parentId":"movies"}]}"#

    @Test func `reads saved rows from Anemone's own entry first`() async throws {
        let server = HomeServer("settings-saved.test") { path, _ in
            path == "/DisplayPreferences/default" ? .displayPreferences(["home_settings": Self.savedJSON]) : nil
        }

        let resolution = try await server.session().resolveHomeSettings()

        #expect(resolution.source == .server)
        #expect(resolution.settings?.rows.map(\.kind) == [.nextUp, .genres(parentID: "movies")])
        let sent = try #require(server.requests(to: "/DisplayPreferences/default").first)
        #expect(sent.query == ["userId": "u1", "client": "Anemone"])
        #expect(!server.paths.contains("/wholphin/public"))
    }

    @Test func `falls back to the server plugin's rows, then to the default`() async throws {
        let withPlugin = HomeServer("settings-plugin.test") { path, _ in
            switch path {
            case "/DisplayPreferences/default": .displayPreferences()
            case "/wholphin/public": .json("{}")
            case "/wholphin/homesettings": .json(Self.savedJSON)
            default: nil
            }
        }
        let withoutPlugin = HomeServer("settings-noplugin.test") { path, _ in
            path == "/DisplayPreferences/default" ? .displayPreferences() : .notFound
        }

        let plugin = try await withPlugin.session().resolveHomeSettings()
        let fallback = try await withoutPlugin.session().resolveHomeSettings()

        #expect(plugin.source == .plugin)
        #expect(plugin.settings?.rows.count == 2)
        #expect(fallback == HomeSettingsResolution(settings: nil, source: .default))
        #expect(!withoutPlugin.paths.contains("/wholphin/homesettings"))
    }

    @Test func `settings that can't be read are skipped, but a revoked token isn't`() async throws {
        let unreadable = HomeServer("settings-unreadable.test") { path, _ in
            switch path {
            case "/DisplayPreferences/default": .displayPreferences(["home_settings": #"{"version":9,"rows":[]}"#])
            default: .notFound
            }
        }
        let revoked = HomeServer("settings-revoked.test") { _, _ in .unauthorized }

        let resolution = try await unreadable.session().resolveHomeSettings()

        #expect(resolution.source == .default)
        await #expect(throws: SessionError.signedOut) {
            try await revoked.session().resolveHomeSettings()
        }
    }

    @Test func `imports from Wholphin's entry`() async throws {
        let server = HomeServer("settings-wholphin.test") { path, request in
            guard path == "/DisplayPreferences/default", request.query["client"] == "Wholphin" else { return nil }
            return .displayPreferences(["home_settings": Self.savedJSON])
        }

        let settings = try await server.session().savedHomePageSettings(client: HomeDisplayPreferences.wholphinClient)

        #expect(settings?.rows.first?.kind == .nextUp)
    }

    @Test func `the plugin's home settings are none when it has no rows or isn't there`() async throws {
        let empty = HomeServer("plugin-empty.test") { path, _ in
            path == "/wholphin/homesettings" ? .json(#"{"version":1,"rows":[]}"#) : nil
        }
        let missing = HomeServer("plugin-missing.test") { _, _ in .notFound }
        let broken = HomeServer("plugin-broken.test") { _, _ in MockServer.Reply(status: 500, body: "") }

        let fromEmpty = try await empty.session().serverPluginHomePageSettings()
        let fromMissing = try await missing.session().serverPluginHomePageSettings()
        #expect(fromEmpty == nil)
        #expect(fromMissing == nil)
        #expect(try await missing.session().isServerPluginInstalled() == false)
        await #expect(throws: (any Error).self) {
            try await broken.session().serverPluginHomePageSettings()
        }
    }

    @Test func `saving keeps the entry's other keys`() async throws {
        let server = HomeServer("settings-save.test") { path, request in
            guard path == "/DisplayPreferences/default" else { return nil }
            if request.method == "POST" {
                return MockServer.Reply(status: 204, body: "")
            }
            return .displayPreferences(["removeNextUp": #"{"value":{}}"#])
        }
        let writer = try HomePreferencesWriter(session: server.session())
        let settings = HomePageSettings(rows: [HomeRowConfig(.continueWatchingCombined)])

        try await writer.save(settings)

        let sent = try #require(server.requests(to: "/DisplayPreferences/default").last { $0.method == "POST" })
        #expect(sent.query == ["userId": "u1", "client": "Anemone"])
        let prefs = try #require(sent.json["CustomPrefs"] as? [String: String])
        #expect(prefs["removeNextUp"] == #"{"value":{}}"#)
        #expect(try HomePageSettings(json: #require(prefs["home_settings"])) == settings)
    }

    @Test func `reset forgets the saved rows and keeps the entry's other keys`() async throws {
        let server = HomeServer("settings-reset.test") { path, request in
            guard path == "/DisplayPreferences/default" else { return nil }
            if request.method == "POST" {
                return MockServer.Reply(status: 204, body: "")
            }
            return .displayPreferences(["removeNextUp": #"{"value":{}}"#, "home_settings": Self.savedJSON])
        }

        try await HomePreferencesWriter(session: server.session()).forgetHomePageSettings()

        let sent = try #require(server.requests(to: "/DisplayPreferences/default").last { $0.method == "POST" })
        #expect(sent.json["CustomPrefs"] as? [String: String] == ["removeNextUp": #"{"value":{}}"#])
    }

    @Test func `an entry with nulls in it is read, and saved with its other fields`() async throws {
        // What Jellyfin 12.3 sends for a client that never saved anything, plus a saved key.
        let escaped = Self.savedJSON.replacingOccurrences(of: "\"", with: "\\\"")
        let entry = #"""
        {"Id":"default","SortBy":"SortName","RememberIndexing":false,"PrimaryImageHeight":250,
         "ScrollDirection":"Horizontal","SortOrder":"Ascending","Client":"Anemone",
         "CustomPrefs":{"tvhome":null,"home_settings":"\#(escaped)"}}
        """#
        let server = HomeServer("settings-nulls.test") { path, request in
            guard path == "/DisplayPreferences/default" else { return nil }
            return request.method == "POST" ? MockServer.Reply(status: 204, body: "") : .json(entry)
        }
        let session = try server.session()

        let saved = try await session.savedHomePageSettings()
        try await HomePreferencesWriter(session: session).update { $0["removeNextUp"] = #"{"value":{}}"# }

        #expect(saved?.rows.count == 2)
        let posted = try #require(server.requests(to: "/DisplayPreferences/default").last { $0.method == "POST" })
        #expect(posted.json["SortBy"] as? String == "SortName")
        #expect(posted.json["PrimaryImageHeight"] as? Int == 250)
        #expect(posted.json["RememberIndexing"] as? Bool == false)
        let prefs = try #require(posted.json["CustomPrefs"] as? [String: String])
        #expect(prefs["home_settings"] == Self.savedJSON)
        #expect(prefs["removeNextUp"] == #"{"value":{}}"#)
    }

    @Test func `removing from next up marks the episode unwatched and notes its series`() async throws {
        let server = HomeServer("settings-remove.test") { path, request in
            switch (path, request.method) {
            case ("/UserPlayedItems/e1", "DELETE"):
                .json(#"{"Key":"e1","Played":false}"#)
            case ("/DisplayPreferences/default", "POST"):
                MockServer.Reply(status: 204, body: "")
            case ("/DisplayPreferences/default", _):
                .displayPreferences(["home_settings": Self.savedJSON])
            default:
                nil
            }
        }
        let session = try server.session()
        let writer = HomePreferencesWriter(session: session)
        let episode = MediaItem(
            id: "e1",
            name: "Pilot",
            kind: .episode,
            episode: .init(seriesID: "1dd1c2fd2e1b48e4ba9417a2350fe9cf", seriesName: "Show"),
        )
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        try await writer.removeFromNextUp(episode, session: session, now: now)

        #expect(server.requests(to: "/UserPlayedItems/e1").count == 1)
        let posted = server.requests(to: "/DisplayPreferences/default").last { $0.method == "POST" }
        let prefs = try #require(posted?.json["CustomPrefs"] as? [String: String])
        #expect(prefs["home_settings"] == Self.savedJSON)
        let removedJSON = try #require(prefs["removeNextUp"])
        #expect(removedJSON.contains("1dd1c2fd-2e1b-48e4-ba94-17a2350fe9cf"))
        let removed = try RemovedFromNextUp(json: removedJSON)
        #expect(removed.dates == ["1dd1c2fd2e1b48e4ba9417a2350fe9cf": now])
    }

    @Test func `changes are saved one at a time`() async throws {
        let stored = Stored()
        let server = HomeServer("settings-serial.test") { path, request in
            guard path == "/DisplayPreferences/default" else { return nil }
            if request.method == "POST" {
                let prefs = request.json["CustomPrefs"] as? [String: String] ?? [:]
                stored.prefs.withLock { $0 = prefs }
                return MockServer.Reply(status: 204, body: "")
            }
            return .displayPreferences(stored.prefs.withLock(\.self))
        }
        let writer = try HomePreferencesWriter(session: server.session())

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0 ..< 5 {
                group.addTask { try await writer.update { $0["key\(index)"] = "\(index)" } }
            }
            try await group.waitForAll()
        }

        #expect(stored.prefs.withLock(\.self).count == 5)
    }

    @Test func `reads Wholphin's removal dates`() throws {
        let json = #"{"value":{"1dd1c2fd-2e1b-48e4-ba94-17a2350fe9cf":"2026-10-25T10:00:00.123456789"}}"#

        let removed = try RemovedFromNextUp(json: json)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let expected = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 25, hour: 10, minute: 0, second: 0,
        )))
        let date = try #require(removed.dates["1dd1c2fd2e1b48e4ba9417a2350fe9cf"])
        #expect(abs(date.timeIntervalSince(expected) - 0.123456789) < 0.001)
        let again = try RemovedFromNextUp(json: removed.json())
        #expect(abs((again.dates.values.first ?? .distantPast).timeIntervalSince(date)) < 0.001)
    }

    @Test func `combining and splitting watching rows keeps their place and look`() {
        var look = HomeRowViewOptions()
        look.showTitles = true
        let rows = [
            HomeRowConfig(.recentlyAdded(parentID: "movies")),
            HomeRowConfig(.continueWatching, viewOptions: look),
            HomeRowConfig(.genres(parentID: "movies")),
            HomeRowConfig(.nextUp),
        ]

        let combined = rows.combiningWatchingRows()
        let split = combined.splittingWatchingRows()

        #expect(combined.map(\.kind) == [
            .recentlyAdded(parentID: "movies"), .continueWatchingCombined, .genres(parentID: "movies"),
        ])
        #expect(combined[1].viewOptions == look)
        #expect(split.map(\.kind) == [
            .recentlyAdded(parentID: "movies"), .continueWatching, .nextUp, .genres(parentID: "movies"),
        ])
        #expect(split[2].viewOptions == look)
    }

    @Test func `row IDs are stable and readable`() {
        let ids = HomeRowConfig.rowIDs(for: [
            HomeRowConfig(.continueWatchingCombined),
            HomeRowConfig(.genres(parentID: "movies")),
            HomeRowConfig(.genres(parentID: "movies")),
            HomeRowConfig(.favorite(itemKind: "Movie")),
        ])

        #expect(ids == ["continueWatching", "genres.movies", "genres.movies.2", "favorite.Movie"])
    }

    @Test func `the add row page offers Wholphin's row types for each library`() {
        let shows = Library(id: "shows", name: "Shows", kind: .shows)
        let music = Library(id: "music", name: "Music", kind: .music)

        #expect(HomeLibraryRowType.available(for: shows).contains(.studios))
        #expect(!HomeLibraryRowType.available(for: music).contains(.suggestions))
        #expect(HomeLibraryRowType.recentlyAdded.row(for: music).viewOptions.aspectRatio == .square)
        #expect(HomeFavoriteKind.available(for: [shows, music]) == [
            "Series", "Episode", "Person", "MusicAlbum", "MusicArtist", "Audio",
        ])
    }
}

/// What a fake server holds, shared with its handler.
private final class Stored: Sendable {
    let prefs = Mutex<[String: String]>([:])
}
