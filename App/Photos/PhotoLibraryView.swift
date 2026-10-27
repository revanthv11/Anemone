import AnemoneJellyfin
import SwiftUI

/// A photo library, which gets Wholphin's albums and slideshow in Phase 5
/// (`CollectionFolderPhotoAlbum`). The library grid until then.
struct PhotoLibraryView: View {
    let library: Library
    @Binding var path: NavigationPath

    var body: some View {
        LibraryScreen(library: library, path: $path)
    }
}
