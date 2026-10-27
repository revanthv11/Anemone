import AnemoneJellyfin
import SwiftUI

/// A photo library, or a home videos and photos one, as Wholphin's `CollectionFolderPhotoAlbum`
/// shows both: its albums, photos and clips in a grid. Albums open the same way, a photo opens
/// in the slideshow's viewer, and Play shows everything in the library as a slideshow.
struct PhotoLibraryView: View {
    let library: Library
    @Binding var path: NavigationPath

    var body: some View {
        PhotoFolderPage(folder: PhotoFolder(library: library), path: $path)
            .navigationDestination(for: PhotoFolder.self) { folder in
                PhotoFolderPage(folder: folder, path: $path)
            }
    }
}

/// A photo library or one of its albums.
struct PhotoFolder: Hashable {
    let id: String
    let name: String
    /// The kind of library it's in, which sets the grid's defaults.
    let libraryKind: Library.Kind
    let isAlbum: Bool

    init(library: Library) {
        id = library.id
        name = library.name
        libraryKind = library.kind
        isAlbum = false
    }

    init(album: MediaItem, in parent: PhotoFolder) {
        id = album.id
        name = album.name
        libraryKind = parent.libraryKind
        isAlbum = true
    }

    /// The folder as a library, which is how the grid's requests and saved settings know it.
    var library: Library {
        Library(id: id, name: name, kind: libraryKind)
    }
}
