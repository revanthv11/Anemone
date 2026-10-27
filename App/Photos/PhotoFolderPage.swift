import AnemoneCore
import AnemoneJellyfin
import AnemonePlayback
import AnemoneUI
import SwiftUI

/// A photo library's or album's grid, ported from Wholphin's `CollectionFolderPhotoAlbum`: 16:9
/// cards, four across, under a header with the sort, Random, and Play and Shuffle, which start a
/// slideshow of every photo inside, albums included. The sort is kept per library and album.
struct PhotoFolderPage: View {
    let folder: PhotoFolder
    @Binding var path: NavigationPath

    @Environment(BrowseModel.self) private var browse
    @AppStorage(Preferences.slideshowPlayVideos) private var slideshowPlaysVideos
    @State private var sort: LibrarySort?
    @State private var content = Content.loading
    @State private var focusedIndex = 0
    @State private var slideshow: SlideshowStart?
    @FocusState private var isSortFocused: Bool

    private enum Content {
        case loading
        case loaded(LibraryPager)
        case failed
        case signedOut

        var isLoaded: Bool {
            if case .loaded = self {
                true
            } else {
                false
            }
        }
    }

    var body: some View {
        Group {
            switch content {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .loaded(pager):
                grid(pager)
            case .failed:
                message("Couldn't load \(folder.name) from \(browse.server.name).") {
                    Button("Try again") {
                        Task { await load() }
                    }
                }
            case .signedOut:
                message("\(browse.server.name) signed you out. Go to Home to sign in again.") {}
            }
        }
        .task {
            if sort == nil {
                sort = browse.libraryPreferences.settings(for: folder.library).sort
            }
        }
        .task(id: query) {
            await load()
        }
        .fullScreenCover(item: $slideshow) { start in
            SlideshowView(start: start)
        }
    }

    private func grid(_ pager: LibraryPager) -> some View {
        LibraryGrid(
            pager: pager,
            options: GridViewOptions.defaults(for: folder.libraryKind),
            showsJumpBar: currentSort.field == .name && pager.count > 0,
            position: { letter in
                guard let query else { return 0 }
                return try await browse.session.position(of: letter, in: query, count: pager.count)
            },
            imageURL: { item, shape, pixels in
                browse.imageURL(item.image(for: shape), width: CGFloat(pixels))
            },
            onSelect: open,
            onFocus: { focusedIndex = $0 },
            header: {
                header(count: pager.count) {
                    Button("Random", systemImage: "dice") {
                        openRandom(from: pager)
                    }
                    .accessibilityIdentifier("photos.random")
                    Button("Play", systemImage: "play.fill") {
                        startSlideshow(shuffled: false)
                    }
                    .accessibilityIdentifier("photos.play")
                    Button("Shuffle", systemImage: "shuffle") {
                        startSlideshow(shuffled: true)
                    }
                    .accessibilityIdentifier("photos.shuffle")
                }
                .disabled(pager.count == 0)
            },
        )
        // An album opens with focus on the sort, above its first cards. Otherwise the grid's
        // alphabet bar, whose default focus is the only one on the page, takes it.
        .defaultFocus($isSortFocused, folder.isAlbum)
    }

    private func header(count: Int?, @ViewBuilder trailing: () -> some View = { EmptyView() }) -> some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text(folder.name)
                    .font(.title2.bold())
                    .lineLimit(1)
                if let count {
                    Text(count == 1 ? "1 item" : "\(count.formatted()) items")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            PhotoSortMenu(sort: sortBinding)
                .focused($isSortFocused)
            trailing()
        }
        .font(.callout)
    }

    private func message(_ text: String, @ViewBuilder actions: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 40) {
            header(count: nil)
                .focusSection()
            VStack(spacing: 24) {
                Text(text)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                actions()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, GridLayout.horizontalInset)
        .padding(.vertical, GridLayout.focusPadding)
    }

    private var currentSort: LibrarySort {
        sort ?? .default
    }

    private var query: LibraryQuery? {
        sort.map { LibraryQuery(library: folder.library, sort: $0) }
    }

    private var sortBinding: Binding<LibrarySort> {
        Binding { currentSort } set: { newSort in
            sort = newSort
            var settings = browse.libraryPreferences.settings(for: folder.library)
            settings.sort = newSort
            browse.libraryPreferences.save(settings, for: folder.library)
        }
    }

    /// As Wholphin's photo grid: an album opens its own grid, a photo opens the viewer on it, and
    /// anything else, such as a clip, opens its page.
    private func open(_ item: MediaItem) {
        switch item.kind {
        case .folder:
            path.append(PhotoFolder(album: item, in: folder))
        case .photo:
            slideshow = SlideshowStart(
                query: SlideshowQuery(folderID: folder.id, sort: currentSort, includesVideos: slideshowPlaysVideos),
                itemID: item.id,
                gridIndex: focusedIndex,
            )
        default:
            path.append(item)
        }
    }

    /// Play and Shuffle: every photo inside, albums included, as a slideshow from the first.
    /// Wholphin's Shuffle shows them in order; here it shuffles.
    private func startSlideshow(shuffled: Bool) {
        let query = SlideshowQuery(
            folderID: folder.id,
            sort: shuffled ? LibrarySort(.random) : currentSort,
            isRecursive: true,
            includesVideos: slideshowPlaysVideos,
        )
        slideshow = SlideshowStart(query: query, runs: true)
    }

    private func openRandom(from pager: LibraryPager) {
        Task {
            guard pager.count > 0 else { return }
            let index = Int.random(in: 0 ..< pager.count)
            if let entry = try? await pager.load(at: index) {
                focusedIndex = index
                open(entry.item)
            }
        }
    }

    /// Loads the first page for the current sort. The old grid stays up meanwhile, so focus
    /// stays on the sort menu.
    private func load() async {
        guard let query else { return }
        if !content.isLoaded {
            content = .loading
        }
        let session = browse.session
        let pager = LibraryPager { startIndex, limit, includeTotalCount in
            try await session.libraryItems(
                query,
                startIndex: startIndex,
                limit: limit,
                includeTotalCount: includeTotalCount,
            )
        }
        do {
            try await pager.start()
            guard !Task.isCancelled else { return }
            content = .loaded(pager)
        } catch SessionError.signedOut {
            browse.noteSignedOut()
            content = .signedOut
        } catch {
            guard !Task.isCancelled else { return }
            content = .failed
        }
    }
}

/// Wholphin's sort button, with the orders that mean something for photos. Picking the current
/// one again reverses it.
private struct PhotoSortMenu: View {
    @Binding var sort: LibrarySort

    private static let fields: [LibrarySort.Field] = [.name, .premiereDate, .dateCreated, .random]

    var body: some View {
        Menu {
            ForEach(Self.fields, id: \.self) { field in
                Button {
                    sort = sort.choosing(field)
                } label: {
                    if field == sort.field {
                        Label(Self.title(field), systemImage: sort.direction.systemImage)
                    } else {
                        Text(Self.title(field))
                    }
                }
            }
        } label: {
            Label(Self.title(sort.field), systemImage: sort.direction.systemImage)
        }
        .accessibilityIdentifier("photos.sort")
    }

    private static func title(_ field: LibrarySort.Field) -> String {
        switch field {
        // Jellyfin keeps when a photo was taken as its premiere date.
        case .premiereDate: "Date Taken"
        default: field.title
        }
    }
}
