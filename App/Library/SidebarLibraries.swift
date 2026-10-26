import AnemoneJellyfin
import SwiftUI

/// Settings › Sidebar: which libraries the sidebar shows and in what order, like Wholphin's
/// "Customize Navigation Drawer Items". Libraries switched off move to More.
struct SidebarSettingsView: View {
    @Environment(BrowseModel.self) private var browse

    var body: some View {
        let preferences = browse.libraryPreferences
        let libraries = preferences.pins.ordered(browse.libraries, id: \.id)
        let ids = libraries.map(\.id)
        List {
            Section {
                ForEach(Array(libraries.enumerated()), id: \.element.id) { offset, library in
                    HStack(spacing: 24) {
                        Toggle(isOn: Binding {
                            preferences.pins.isPinned(library.id)
                        } set: { pinned in
                            preferences.updatePins { $0.setPinned(pinned, library.id) }
                        }) {
                            Label(library.name, systemImage: library.systemImage)
                        }
                        .accessibilityIdentifier("sidebar.pin.\(library.id)")
                        Button("Move up", systemImage: "chevron.up") {
                            preferences.updatePins { $0.move(library.id, by: -1, in: ids) }
                        }
                        .labelStyle(.iconOnly)
                        .disabled(offset == 0)
                        Button("Move down", systemImage: "chevron.down") {
                            preferences.updatePins { $0.move(library.id, by: 1, in: ids) }
                        }
                        .labelStyle(.iconOnly)
                        .disabled(offset == libraries.count - 1)
                    }
                }
            } footer: {
                Text(libraries.isEmpty
                    ? "Your libraries appear here once they've loaded."
                    : "Libraries you switch off move to More in the sidebar.")
            }
        }
        .navigationTitle("Sidebar")
    }
}

/// The libraries unpinned from the sidebar, like the More section of Wholphin's drawer.
struct MoreLibrariesView: View {
    let libraries: [Library]

    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            List(libraries) { library in
                NavigationLink(value: library) {
                    Label(library.name, systemImage: library.systemImage)
                }
            }
            .navigationTitle("More")
            .navigationDestination(for: Library.self) { library in
                LibraryRoot(library: library, path: $path)
            }
            .navigationDestination(for: MediaItem.self) { item in
                ItemDetailView(item: item)
            }
        }
    }
}
