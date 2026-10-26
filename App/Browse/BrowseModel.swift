import AnemoneCore
import AnemoneJellyfin
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
    private(set) var home = HomeState.loading
    /// Kept through reloads, so the sidebar doesn't flicker.
    private(set) var libraries: [Library] = []
    @ObservationIgnored private var didPlaceInitialFocus = false

    init(session: JellyfinSession, server: SavedServer) {
        self.session = session
        self.server = server
    }

    func load() async {
        home = .loading
        do {
            let content = try await session.home()
            libraries = content.libraries
            home = .loaded(content)
        } catch SessionError.signedOut {
            home = .signedOut
        } catch {
            home = .failed
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
}
