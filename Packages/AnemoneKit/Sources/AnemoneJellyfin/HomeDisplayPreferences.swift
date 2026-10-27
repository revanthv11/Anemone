import AnemoneCore
import Foundation

/// Where the home page's settings live on the server: a DisplayPreferences entry's
/// `customPrefs`, as Wholphin keeps them (`DisplayPreferencesService`). Anemone writes only its own
/// entry, under client `Anemone`; Wholphin's is read for "Import from Wholphin".
public enum HomeDisplayPreferences {
    public static let id = "default"
    public static let anemoneClient = "Anemone"
    /// Wholphin's release builds; debug builds use "Wholphin (Debug)".
    public static let wholphinClient = "Wholphin"
    /// Wholphin's `HomeSettingsService.CUSTOM_PREF_ID`.
    static let homeSettingsKey = "home_settings"
    /// Wholphin's `LatestNextUpService.REMOVED_KEY`.
    static let removedNextUpKey = "removeNextUp"
}

/// Where the rows on the home page came from, like Wholphin's `HomePageSettingsSource`.
public enum HomeSettingsSource: Hashable, Sendable {
    /// Saved on the server for this user, under client `Anemone`.
    case server
    /// The server plugin's rows for every user.
    case plugin
    /// Built from the user's libraries; nothing is saved until the user changes something.
    case `default`
}

/// The rows to show, and where they came from.
public struct HomeSettingsResolution: Hashable, Sendable {
    /// `nil` for the default rows, which depend on the libraries.
    public var settings: HomePageSettings?
    public var source: HomeSettingsSource
    /// The series taken out of Next Up, read from the same entry as the saved rows, so loading
    /// the page needn't read it again. `nil` when the entry couldn't be read.
    public var removedFromNextUp: RemovedFromNextUp?

    public init(
        settings: HomePageSettings?,
        source: HomeSettingsSource,
        removedFromNextUp: RemovedFromNextUp? = nil,
    ) {
        self.settings = settings
        self.source = source
        self.removedFromNextUp = removedFromNextUp
    }
}

public extension JellyfinSession {
    /// The rows saved under `client`, or `nil` when there are none.
    ///
    /// - Throws: `HomeSettingsError.unsupportedVersion` for settings from a newer schema.
    func savedHomePageSettings(client: String = HomeDisplayPreferences.anemoneClient) async throws
        -> HomePageSettings?
    {
        let prefs = try await customPrefs(client: client)
        return try prefs[HomeDisplayPreferences.homeSettingsKey].map(HomePageSettings.init(json:))
    }

    /// Finds the rows to show the way Wholphin's `loadInOrder` does, minus its device-only copy:
    /// those saved on the server for this user, then the server plugin's, then none (the
    /// default). A source that fails is skipped, but a revoked token isn't.
    ///
    /// Anemone's entry is read once, for the rows and the series removed from Next Up. Whether
    /// the server has the plugin is asked once per `cache`, which lasts the session.
    func resolveHomeSettings(cache: HomeCache? = nil) async throws -> HomeSettingsResolution {
        let prefs = try await skippingFailures { try await customPrefs(client: HomeDisplayPreferences.anemoneClient) }
        let removed = prefs.map(RemovedFromNextUp.init(customPrefs:))
        let saved = try await skippingFailures {
            try prefs?[HomeDisplayPreferences.homeSettingsKey].map(HomePageSettings.init(json:))
        }
        if let saved {
            return HomeSettingsResolution(settings: saved, source: .server, removedFromNextUp: removed)
        }
        if await hasServerPlugin(cache: cache),
           let settings = try await skippingFailures({ try await serverPluginHomePageSettings() })
        {
            return HomeSettingsResolution(settings: settings, source: .plugin, removedFromNextUp: removed)
        }
        return HomeSettingsResolution(settings: nil, source: .default, removedFromNextUp: removed)
    }

    /// One DisplayPreferences entry's `customPrefs` that have a value. An entry that was never
    /// saved comes back empty.
    func customPrefs(client: String, id: String = HomeDisplayPreferences.id) async throws -> [String: String] {
        try await displayPreferences(client: client, id: id).customPrefs
    }

    /// Whether the server has the plugin, kept in `cache` once known. When the server couldn't be
    /// asked, it counts as no, as in Wholphin, and is asked again next time.
    private func hasServerPlugin(cache: HomeCache?) async -> Bool {
        if let known = await cache?.isServerPluginInstalled {
            return known
        }
        guard let installed = try? await serverPluginProbe() else { return false }
        await cache?.setServerPluginInstalled(installed)
        return installed
    }

    private func skippingFailures<Value>(_ load: () async throws -> Value?) async throws -> Value? {
        do {
            return try await load()
        } catch SessionError.signedOut {
            throw SessionError.signedOut
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
    }
}

/// Saves changes to Anemone's DisplayPreferences entry one at a time. Each change reads the entry
/// afresh and writes it back whole, so changes to other keys, such as Next Up removals, aren't
/// lost; Wholphin's `DisplayPreferencesService` uses a mutex for the same reason.
public actor HomePreferencesWriter {
    private let session: JellyfinSession
    private let client: String
    /// The change under way, which the next one waits for.
    private var last: Task<Void, Never>?

    public init(session: JellyfinSession, client: String = HomeDisplayPreferences.anemoneClient) {
        self.session = session
        self.client = client
    }

    /// Saves the home page's rows, replacing any saved before.
    public func save(_ settings: HomePageSettings) async throws {
        let json = try settings.json()
        try await update { $0[HomeDisplayPreferences.homeSettingsKey] = json }
    }

    /// Forgets the saved rows, Wholphin's "Reset", keeping the entry's other keys.
    public func forgetHomePageSettings() async throws {
        try await update { $0[HomeDisplayPreferences.homeSettingsKey] = nil }
    }

    /// Changes the entry's `customPrefs`, after any change already under way.
    public func update(_ change: @escaping @Sendable (inout [String: String]) throws -> Void) async throws {
        let previous = last
        let session = session
        let client = client
        let task = Task {
            await previous?.value
            var entry = try await session.displayPreferences(client: client, id: HomeDisplayPreferences.id)
            var prefs = entry.customPrefs
            try change(&prefs)
            entry.customPrefs = prefs
            try await session.saveDisplayPreferences(entry, client: client, id: HomeDisplayPreferences.id)
        }
        last = Task { _ = await task.result }
        try await task.value
    }
}
