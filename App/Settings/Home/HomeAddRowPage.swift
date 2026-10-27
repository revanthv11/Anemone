import AnemoneCore
import AnemoneJellyfin
import SwiftUI

/// Settings › Home › Add row, like Wholphin's: the watching rows, each library's row types,
/// favourites by type, and a collection's or playlist's items. On one page, so adding a row goes
/// straight back to the list, where it's last.
struct HomeAddRowPage: View {
    @Environment(BrowseModel.self) private var browse
    @Environment(\.dismiss) private var dismiss
    @State private var collections: [MediaItem] = []
    @State private var playlists: [MediaItem] = []

    var body: some View {
        List {
            Section("Continue watching") {
                add(String(localized: "Continue Watching"), id: "continueWatching", HomeRowConfig(.continueWatching))
                add(String(localized: "Next Up"), id: "nextUp", HomeRowConfig(.nextUp))
                add(
                    String(localized: "Combine Continue Watching & Next Up"),
                    id: "combined",
                    HomeRowConfig(.continueWatchingCombined),
                )
            }
            ForEach(browse.libraries) { library in
                Section(library.name) {
                    ForEach(HomeLibraryRowType.available(for: library), id: \.self) { type in
                        add(type.title, id: "\(library.id).\(type.rawValue)", type.row(for: library))
                    }
                }
            }
            liveTVSection
            Section("Favorites") {
                ForEach(HomeFavoriteKind.available(for: browse.libraries), id: \.self) { kind in
                    add(
                        String(localized: "Favorite \(HomeFavoriteKind.pluralName(kind))"),
                        id: "favorite.\(kind)",
                        HomeRowConfig(.favorite(itemKind: kind)),
                    )
                }
            }
            parentSection(String(localized: "Collections"), collections)
            parentSection(String(localized: "Playlists"), playlists)
        }
        .navigationTitle("Add row")
        .task {
            async let boxSets = try? browse.session.homeParentChoices(itemKind: "BoxSet")
            async let lists = try? browse.session.homeParentChoices(itemKind: "Playlist")
            collections = await boxSets ?? []
            playlists = await lists ?? []
        }
    }

    /// Live TV rows, for a Live TV library or the made-up Live TV of DEBUG builds.
    @ViewBuilder
    private var liveTVSection: some View {
        if offersLiveTV, !browse.libraries.contains(where: { $0.kind == .liveTV }) {
            Section("Live TV") {
                add(String(localized: "Watch Live"), id: "tvPrograms", HomeRowConfig(.tvPrograms))
                add(String(localized: "Channels"), id: "tvChannels", HomeRowConfig(.tvChannels))
                add(String(localized: "Active Recordings"), id: "recordings", HomeRowConfig(.recordings))
            }
        }
    }

    private var offersLiveTV: Bool {
        #if DEBUG
            UserDefaults.standard.bool(forKey: "homeMockLiveTV")
        #else
            false
        #endif
    }

    @ViewBuilder
    private func parentSection(_ title: String, _ parents: [MediaItem]) -> some View {
        if !parents.isEmpty {
            Section(title) {
                ForEach(parents) { parent in
                    add(
                        parent.name,
                        id: "byParent.\(parent.id)",
                        HomeRowConfig(.byParent(parentID: parent.id, recursive: false, sort: nil)),
                    )
                }
            }
        }
    }

    private func add(_ title: String, id: String, _ row: HomeRowConfig) -> some View {
        Button(title) {
            browse.setHomeRows((browse.homeRows ?? []) + [row])
            dismiss()
        }
        .accessibilityIdentifier("settings.home.add.\(id)")
    }
}
