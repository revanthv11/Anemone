import AnemoneCore
import AnemoneJellyfin
import SwiftUI

/// The signed-in app: a sidebar with Home, Search, the user's libraries and Settings, in place
/// of Wholphin's navigation drawer.
struct SignedInView: View {
    enum Destination: Hashable {
        case home
        case search
        case library(Library.ID)
        case settings
    }

    let server: SavedServer
    let user: SavedUser

    @State private var browse: BrowseModel
    @State private var selection = Destination.home

    init(server: SavedServer, user: SavedUser, session: JellyfinSession) {
        self.server = server
        self.user = user
        _browse = State(initialValue: BrowseModel(session: session, server: server))
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house", value: Destination.home) {
                HomeView()
            }
            Tab("Search", systemImage: "magnifyingglass", value: Destination.search, role: .search) {
                PlaceholderPage(title: "Search", message: "Search arrives later in Phase 2.")
            }
            TabSection("Libraries") {
                ForEach(browse.libraries) { library in
                    Tab(library.name, systemImage: library.systemImage, value: Destination.library(library.id)) {
                        PlaceholderPage(title: library.name, message: "Library grids arrive in Phase 2b.")
                    }
                }
            }
            Tab("Settings", systemImage: "gearshape", value: Destination.settings) {
                SettingsView(server: server, user: user)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .environment(browse)
        .task {
            await browse.load()
        }
    }
}

/// Switching and locking profiles, and signing out.
private struct SettingsView: View {
    let server: SavedServer
    let user: SavedUser

    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 32) {
                Text("Settings")
                    .font(.largeTitle.bold())
                VStack(alignment: .leading, spacing: 8) {
                    Text("Signed in as \(user.name)")
                        .font(.title3)
                        .accessibilityIdentifier("settings.signedInAs")
                    Text("\(server.name) · Jellyfin \(server.version)")
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 20) {
                    Button("Switch user") {
                        model.switchUser()
                    }
                    NavigationLink("Profile lock") {
                        ProfileLockView(user: user)
                    }
                    Button("Sign out") {
                        model.signOut()
                    }
                    .accessibilityIdentifier("settings.signOut")
                }
                .padding(.top, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(80)
        }
    }
}

/// A tab whose real screen comes in a later phase.
private struct PlaceholderPage: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(title)
                .font(.largeTitle.bold())
            Text(message)
                .foregroundStyle(.secondary)
        }
        // Gives focus somewhere to rest, so pressing left opens the sidebar again.
        .focusable()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(80)
    }
}

private extension Library {
    var systemImage: String {
        switch kind {
        case .movies: "film"
        case .shows: "tv"
        case .music: "music.note"
        case .musicVideos: "music.note.tv"
        case .homeVideos: "video"
        case .photos: "photo.on.rectangle"
        case .collections: "square.stack"
        case .playlists: "music.note.list"
        case .liveTV: "antenna.radiowaves.left.and.right"
        case .books: "book"
        case .folders, .mixed, .trailers, .other: "folder"
        }
    }
}
