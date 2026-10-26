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
}
