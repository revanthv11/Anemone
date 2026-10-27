import AnemoneJellyfin
import SwiftUI

/// A music library, which gets Wholphin's albums, artists, songs and genres in Phase 5
/// (`CollectionFolderMusic`). The library grid until then.
struct MusicLibraryView: View {
    let library: Library
    @Binding var path: NavigationPath

    var body: some View {
        LibraryScreen(library: library, path: $path)
    }
}
