import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// A library pinned to the sidebar, with its own navigation.
struct LibraryTab: View {
    let library: Library

    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            LibraryRoot(library: library, path: $path)
                .navigationDestination(for: MediaItem.self) { item in
                    ItemDetailView(item: item)
                }
        }
    }
}

/// A library's grid, or a placeholder for Live TV, which gets a guide in Phase 5.
struct LibraryRoot: View {
    let library: Library
    @Binding var path: NavigationPath

    var body: some View {
        if library.hasGrid {
            LibraryScreen(library: library, path: $path)
        } else {
            Text("The Live TV guide arrives in Phase 5.")
                .foregroundStyle(.secondary)
                // Gives focus somewhere to rest, so pressing left opens the sidebar again.
                .focusable()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Wholphin's library page: the grid under a header with the library's name, sort, filters,
/// view options and a random pick. Settings are kept per library.
struct LibraryScreen: View {
    let library: Library
    @Binding var path: NavigationPath

    @Environment(BrowseModel.self) private var browse
    @State private var settings: LibraryDisplaySettings?
    @State private var content = Content.loading
    @State private var isReloading = false
    @State private var showsFilters = false
    @State private var showsViewOptions = false
    @State private var filterChoices = FilterChoiceCache()

    private enum Content {
        case loading
        case loaded(LibraryPager)
        case failed
        case signedOut
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
                message("Couldn't load \(library.name) from \(browse.server.name).") {
                    Button("Try again") {
                        Task { await load() }
                    }
                }
            case .signedOut:
                message("\(browse.server.name) signed you out. Go to Home to sign in again.") {}
            }
        }
        .task {
            if settings == nil {
                settings = browse.libraryPreferences.settings(for: library)
            }
        }
        .task(id: query) {
            await load()
        }
        .sheet(isPresented: $showsFilters) {
            FilterSheet(library: library, filter: filterBinding, cache: filterChoices)
        }
        .sheet(isPresented: $showsViewOptions) {
            ViewOptionsSheet(options: viewOptionsBinding, defaults: GridViewOptions.defaults(for: library.kind))
        }
    }

    private func grid(_ pager: LibraryPager) -> some View {
        let sort = settings?.sort ?? .default
        return LibraryGrid(
            pager: pager,
            options: viewOptions,
            showsJumpBar: sort.field == .name && pager.count > 0,
            position: { letter in
                guard let query else { return 0 }
                return try await browse.session.position(of: letter, in: query, count: pager.count)
            },
            imageURL: { item, shape, pixels in
                browse.imageURL(item.image(for: shape), width: CGFloat(pixels))
            },
            onSelect: { path.append($0) },
            header: {
                header(count: pager.count) {
                    Button("Random", systemImage: "dice") {
                        openRandom(from: pager)
                    }
                    .disabled(pager.count == 0)
                }
            },
        )
        .overlay {
            if isReloading {
                ProgressView()
            }
        }
        .overlay(alignment: .bottom) {
            if pager.error != nil {
                // Cleared when a page loads; cards retry their page as they come back on screen.
                NoticeText("Some items couldn't be loaded from \(browse.server.name).")
                    .padding(.bottom, 60)
            }
        }
        .onChange(of: pager.error as? SessionError) { _, error in
            if error == .signedOut {
                browse.noteSignedOut()
                content = .signedOut
            }
        }
    }

    private func header(count: Int?, @ViewBuilder trailing: () -> some View = { EmptyView() }) -> some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text(library.name)
                    .font(.title2.bold())
                    .lineLimit(1)
                if let count {
                    Text(count == 1 ? "1 item" : "\(count.formatted()) items")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            SortMenu(fields: library.sortFields, sort: sortBinding)
            Button(filterTitle, systemImage: "line.3.horizontal.decrease.circle") {
                showsFilters = true
            }
            .accessibilityIdentifier("library.filter")
            Button("View", systemImage: "square.grid.3x3") {
                showsViewOptions = true
            }
            .accessibilityIdentifier("library.viewOptions")
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

    private var query: LibraryQuery? {
        settings.map { LibraryQuery(library: library, sort: $0.sort, filter: $0.filter) }
    }

    private var viewOptions: GridViewOptions {
        settings?.view ?? .defaults(for: library.kind)
    }

    private var filterTitle: String {
        let active = settings?.filter.activeCount ?? 0
        return active > 0 ? "Filter (\(active))" : "Filter"
    }

    /// Loads the first page for the current sort and filter. The old grid stays up meanwhile, so
    /// focus stays on the sort menu or filter button.
    private func load() async {
        guard let query else { return }
        if case .loaded = content {
            isReloading = true
        } else {
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
            // A newer sort or filter replaced this load.
            guard !Task.isCancelled else { return }
            content = .loaded(pager)
        } catch SessionError.signedOut {
            browse.noteSignedOut()
            content = .signedOut
        } catch {
            guard !Task.isCancelled else { return }
            content = .failed
        }
        isReloading = false
    }

    private func openRandom(from pager: LibraryPager) {
        Task {
            guard pager.count > 0 else { return }
            if let entry = try? await pager.load(at: Int.random(in: 0 ..< pager.count)) {
                path.append(entry.item)
            }
        }
    }

    private func update(_ change: (inout LibraryDisplaySettings) -> Void) {
        var updated = settings ?? browse.libraryPreferences.settings(for: library)
        change(&updated)
        settings = updated
        browse.libraryPreferences.save(updated, for: library)
    }

    private var sortBinding: Binding<LibrarySort> {
        Binding { settings?.sort ?? .default } set: { sort in update { $0.sort = sort } }
    }

    private var filterBinding: Binding<LibraryFilter> {
        Binding { settings?.filter ?? LibraryFilter() } set: { filter in update { $0.filter = filter } }
    }

    private var viewOptionsBinding: Binding<GridViewOptions> {
        Binding { viewOptions } set: { options in update { $0.view = options } }
    }
}

/// Wholphin's sort button: shows the current order; picking the current field again reverses it.
private struct SortMenu: View {
    let fields: [LibrarySort.Field]
    @Binding var sort: LibrarySort

    var body: some View {
        Menu {
            ForEach(fields, id: \.self) { field in
                Button {
                    sort = sort.choosing(field)
                } label: {
                    if field == sort.field {
                        Label(field.title, systemImage: sort.direction.systemImage)
                    } else {
                        Text(field.title)
                    }
                }
            }
        } label: {
            Label(sort.field.title, systemImage: sort.direction.systemImage)
        }
        .accessibilityLabel("Sort by \(sort.field.title), \(sort.direction == .ascending ? "ascending" : "descending")")
        .accessibilityIdentifier("library.sort")
    }
}

extension LibrarySort.Field {
    /// Wholphin's names for its sort options.
    var title: String {
        switch self {
        case .default: "Default"
        case .name: "Name"
        case .premiereDate: "Date Released"
        case .dateCreated: "Date Added"
        case .dateLastContentAdded: "Date Episode Added"
        case .datePlayed, .seriesDatePlayed: "Date Played"
        case .communityRating: "Community Rating"
        case .criticRating: "Critic Rating"
        case .officialRating: "Parental Rating"
        case .runtime: "Runtime"
        case .playCount: "Play Count"
        case .albumArtist: "Album Artist"
        case .random: "Random"
        }
    }
}

extension LibrarySort.Direction {
    var systemImage: String {
        switch self {
        case .ascending: "arrow.up"
        case .descending: "arrow.down"
        }
    }
}
