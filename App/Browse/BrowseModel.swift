import AnemoneCore
import AnemoneJellyfin
import Foundation
import Observation

/// The signed-in user's libraries and home page. One per profile session.
@Observable
final class BrowseModel {
    enum HomeState {
        case loading
        case loaded(HomeContent)
        case failed
        /// The server stopped accepting the token.
        case signedOut
    }

    let session: JellyfinSession
    let server: SavedServer
    let libraryPreferences: LibraryPreferences
    private(set) var home = HomeState.loading
    /// Kept through reloads, so the sidebar doesn't flicker.
    private(set) var libraries: [Library] = []
    /// The rows Home shows, once known: those saved for the user, the server plugin's, or the
    /// default for their libraries.
    private(set) var homeRows: [HomeRowConfig]?
    private(set) var homeRowsSource = HomeSettingsSource.default
    /// Why the last change to Home's rows couldn't be saved on the server, until one is.
    private(set) var homeSaveProblem: String?
    @ObservationIgnored let homeWriter: HomePreferencesWriter
    @ObservationIgnored private let homeCache = HomeCache()
    @ObservationIgnored private var didPlaceInitialFocus = false
    /// The last save of Home's rows, which the next one waits for.
    @ObservationIgnored private var homeSave: Task<Void, Never>?
    /// Goes up with each change to the saved rows, so a save that a newer change overtook is dropped.
    @ObservationIgnored private var homeSaveGeneration = 0

    init(session: JellyfinSession, server: SavedServer) {
        self.session = session
        self.server = server
        libraryPreferences = LibraryPreferences(serverID: server.id, userID: session.userID)
        homeWriter = HomePreferencesWriter(session: session)
    }

    /// Finds Home's rows, as Wholphin does on switching user, then loads them.
    func load() async {
        home = .loading
        do {
            let resolution = try await session.resolveHomeSettings(cache: homeCache)
            let content = try await session.home(
                rows: resolution.settings?.rows,
                removedFromNextUp: resolution.removedFromNextUp,
                options: homeOptions(isRefresh: false),
            )
            homeRows = content.configs
            homeRowsSource = resolution.source
            libraries = content.libraries
            home = .loaded(content)
        } catch SessionError.signedOut {
            home = .signedOut
        } catch {
            home = .failed
        }
    }

    /// Loads the home page again behind the one showing, like Wholphin's refresh on resume, so
    /// Continue Watching and Next Up pick up what was watched elsewhere, and rows changed in
    /// Settings show. Only once Home has loaded; a failed refresh keeps the rows already showing.
    func refresh() async {
        guard case .loaded = home else { return }
        // The default rows follow the libraries, so they're built again: a library added since
        // gets its row.
        let rows = homeRowsSource == .default ? nil : homeRows
        do {
            let content = try await session.home(rows: rows, options: homeOptions(isRefresh: true))
            // Skipped when Home was left meanwhile, or stopped showing rows (reloading, signed out).
            guard !Task.isCancelled, case let .loaded(current) = home else { return }
            if rows == nil, homeRowsSource == .default, homeRows != content.configs {
                // Settings › Home lists them, unless the user saved rows meanwhile.
                homeRows = content.configs
            }
            guard current != content else { return }
            if libraries != content.libraries {
                libraries = content.libraries
            }
            home = .loaded(content)
        } catch SessionError.signedOut {
            noteSignedOut()
        } catch {
            // Keeps what's showing; the next refresh tries again.
        }
    }

    /// True the first time it's called: whether the home page should move focus to its first row.
    func claimInitialFocus() -> Bool {
        defer { didPlaceInitialFocus = true }
        return !didPlaceInitialFocus
    }

    /// Called when a request outside the home page finds the token revoked, so Home shows the
    /// sign-in prompt.
    func noteSignedOut() {
        home = .signedOut
    }

    private func homeOptions(isRefresh: Bool) -> HomeOptions {
        HomeOptions(
            itemsPerRow: Preferences.maxItemsPerRow.value(),
            enableRewatchingNextUp: Preferences.enableRewatchingNextUp.value(),
            maxDaysNextUp: Preferences.maxDaysNextUp.value(),
            liveTV: Self.liveTVSource,
            cache: homeCache,
            isRefresh: isRefresh,
        )
    }
}

// MARK: Changing Home's rows

extension BrowseModel {
    /// Shows `rows` on Home from now on and saves them on the server for the user, under client
    /// `Anemone`, so they follow the user to other Apple TVs. Home picks them up when it next
    /// shows.
    func setHomeRows(_ rows: [HomeRowConfig]) {
        homeRows = rows
        homeRowsSource = .server
        let settings = HomePageSettings(rows: rows)
        homeSaveGeneration += 1
        let generation = homeSaveGeneration
        let previous = homeSave
        // One save at a time, in the order the edits came. A save still waiting when a newer edit
        // comes is dropped, so the server keeps the last edit however quickly they came.
        homeSave = Task {
            await previous?.value
            guard generation == homeSaveGeneration else { return }
            do {
                try await homeWriter.save(settings)
                homeSaveProblem = nil
            } catch {
                homeSaveProblem = problem(with: error, doing: "save your rows on \(server.name)")
            }
        }
    }

    /// Wholphin's "Reset": forgets the rows saved for the user, so Home shows the server plugin's
    /// rows when it has some, and the default rows otherwise.
    func resetHomeRows() async throws {
        // Saves still waiting are dropped, and one under way finishes first, so none can bring
        // the rows back afterwards.
        homeSaveGeneration += 1
        await homeSave?.value
        try await homeWriter.forgetHomePageSettings()
        homeSaveProblem = nil
        let resolution = try await session.resolveHomeSettings(cache: homeCache)
        homeRows = resolution.settings?.rows ?? HomePageSettings.defaultRows(for: libraries)
        homeRowsSource = resolution.source
    }

    /// Replaces Home's rows with those Wholphin saved for the user on this server.
    ///
    /// - Returns: `false` when Wholphin saved none.
    func importHomeRowsFromWholphin() async throws -> Bool {
        guard let settings = try await wholphinHomeSettings(), !settings.rows.isEmpty else { return false }
        setHomeRows(settings.rows)
        return true
    }

    private func wholphinHomeSettings() async throws -> HomePageSettings? {
        #if DEBUG
            if Self.mocksWholphinEntry {
                return HomeDebugData.wholphinSettings(for: libraries)
            }
        #endif
        return try await session.savedHomePageSettings(client: HomeDisplayPreferences.wholphinClient)
    }

    /// Wholphin's "Remove from Next Up": the series stays out of Next Up until one of its
    /// episodes is played again.
    func removeFromNextUp(_ episode: MediaItem) async {
        do {
            try await homeWriter.removeFromNextUp(episode, session: session)
            await refresh()
        } catch SessionError.signedOut {
            noteSignedOut()
        } catch {
            // Home keeps showing it; the user can try again.
        }
    }

    /// Where Home's Live TV rows come from: nothing until Live TV lands, or made-up rows in DEBUG
    /// builds launched with `-homeMockLiveTV YES`.
    static var liveTVSource: any HomeLiveTVSource {
        #if DEBUG
            if UserDefaults.standard.bool(forKey: "homeMockLiveTV") {
                return HomeDebugData.MockLiveTV()
            }
        #endif
        return NoLiveTV()
    }

    #if DEBUG
        /// Launched with `-homeMockWholphin YES`, Import from Wholphin reads made-up rows instead of
        /// the server, which has no Wholphin entry to read.
        static var mocksWholphinEntry: Bool {
            UserDefaults.standard.bool(forKey: "homeMockWholphin")
        }
    #endif
}
