import AnemoneCore
import AnemoneJellyfin
import SwiftUI

/// The signed-in app: a sidebar with Home, Search, Favorites, the user's libraries and Settings,
/// in place of Wholphin's navigation drawer, which also puts Favorites before the libraries.
struct SignedInView: View {
    enum Destination: Hashable {
        case home
        case search
        case favorites
        case library(Library.ID)
        case moreLibraries
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
        let libraries = browse.libraryPreferences.pins.arrange(browse.libraries, id: \.id)
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house", value: Destination.home) {
                HomeView(isSelected: selection == .home)
            }
            Tab("Search", systemImage: "magnifyingglass", value: Destination.search, role: .search) {
                SearchTab(server: server, user: user)
            }
            if FavoritesPage.isAvailable {
                Tab("Favorites", systemImage: "heart", value: Destination.favorites) {
                    FavoritesPage(isSelected: selection == .favorites)
                }
            }
            // Hidden until the libraries load, so the sidebar never shows an empty heading.
            if !browse.libraries.isEmpty {
                TabSection("Libraries") {
                    ForEach(libraries.pinned) { library in
                        Tab(library.name, systemImage: library.systemImage, value: Destination.library(library.id)) {
                            LibraryTab(library: library)
                        }
                    }
                    if !libraries.unpinned.isEmpty {
                        Tab("More", systemImage: "ellipsis.circle", value: Destination.moreLibraries) {
                            MoreLibrariesView(libraries: libraries.unpinned)
                        }
                    }
                }
            }
            Tab("Settings", systemImage: "gearshape", value: Destination.settings) {
                SettingsView(server: server, user: user)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .itemContextActions()
        .environment(browse)
        .musicPlayback(session: browse.session)
        .task {
            await browse.load()
        }
    }
}

/// A tab whose real screen comes in a later phase.
struct PlaceholderPage: View {
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

extension Library {
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
