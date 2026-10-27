import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// Wholphin's library grid page (`CollectionFolderView`): the grid under a header with its name,
/// sort, filters, view options and a random pick. It shows a library's titles (its Library tab),
/// its Collections tab, and the pages its genres and studios open, each with settings of its own.
struct LibraryItemsPage: View {
    let library: Library
    var scope = LibraryQuery.Scope.titles
    /// The header's title, when it isn't the library's name.
    var title: String?
    @Binding var path: NavigationPath
    /// Called as focus moves on from the grid's first row and back to it, for the page's tabs.
    var onPastFirstRow: (Bool) -> Void = { _ in }

    @Environment(BrowseModel.self) private var browse
    @State private var settings: LibraryDisplaySettings?
    @State private var content = Content.loading
    @State private var isReloading = false
    @State private var showsFilters = false
    @State private var showsViewOptions = false
    @State private var filterChoices = FilterChoiceCache()
    @State private var focus = FocusedTitle()

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
                page(pager)
            case .failed:
                message("Couldn't load \(heading) from \(browse.server.name).") {
                    Button("Try again") {
                        Task { await load() }
                    }
                }
            case .signedOut:
                message("\(browse.server.name) signed you out. Go to Home to sign in again.") {}
            }
        }
        .background {
            if viewOptions.showsBackdrop {
                LibraryBackdrop(focus: focus)
            }
        }
        .task {
            if settings == nil {
                settings = browse.libraryPreferences.settings(for: library, page: settingsPage)
            }
        }
        .task(id: query) {
            await load()
        }
        .sheet(isPresented: $showsFilters) {
            FilterSheet(library: library, filter: filterBinding, cache: filterChoices, kinds: filterKinds)
        }
        .sheet(isPresented: $showsViewOptions) {
            ViewOptionsSheet(options: viewOptionsBinding, defaults: defaultViewOptions, showsPageOptions: true)
        }
    }

    /// The grid, with the focused title's details over it, or beside the list, when asked for.
    @ViewBuilder
    private func page(_ pager: LibraryPager) -> some View {
        let options = viewOptions
        switch (options.showsDetails, options.layout) {
        case (true, .grid):
            VStack(alignment: .leading, spacing: 0) {
                LibraryDetailsHeader(focus: focus)
                    .padding(.horizontal, GridLayout.horizontalInset)
                grid(pager)
            }
        case (true, _):
            // The header spans the panel and the list, as in Wholphin, so moving down from the
            // tabs finds it rather than the panel, which holds nothing to focus.
            VStack(alignment: .leading, spacing: 0) {
                gridHeader(pager)
                    .padding(.horizontal, GridLayout.horizontalInset)
                    .padding(.top, GridLayout.focusPadding)
                    .focusSection()
                HStack(alignment: .top, spacing: 0) {
                    LibraryDetailsPanel(focus: focus)
                    grid(pager, withHeader: false)
                }
            }
        case (false, _):
            grid(pager)
        }
    }

    private func grid(_ pager: LibraryPager, withHeader: Bool = true) -> some View {
        let sort = settings?.sort ?? .default
        let options = viewOptions
        let tracksFocus = options.showsDetails || options.showsBackdrop
        return LibraryGrid(
            pager: pager,
            options: options,
            showsJumpBar: sort.field == .name && pager.count > 0,
            position: { letter in
                guard let query else { return 0 }
                return try await browse.session.position(of: letter, in: query, count: pager.count)
            },
            imageURL: { item, shape, pixels in
                browse.imageURL(item.image(for: shape), width: CGFloat(pixels))
            },
            onSelect: { path.append($0) },
            onFocus: { index in
                if tracksFocus {
                    focus.note(pager.item(at: index))
                }
            },
            onPastFirstRow: onPastFirstRow,
            emptyMessage: emptyMessage,
            header: {
                if withHeader {
                    gridHeader(pager)
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
        .onChange(of: ObjectIdentifier(pager), initial: true) {
            // Until a card has focus, the details show the first title.
            if tracksFocus {
                focus.note(pager.item(at: 0))
            }
        }
    }

    private func gridHeader(_ pager: LibraryPager) -> some View {
        header(count: pager.count) {
            Button("Random", systemImage: "dice") {
                openRandom(from: pager)
            }
            .disabled(pager.count == 0)
        }
    }

    private func header(count: Int?, @ViewBuilder trailing: () -> some View = { EmptyView() }) -> some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text(heading)
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
}

/// What the page loads and keeps, and how.
private extension LibraryItemsPage {
    var heading: String {
        title ?? library.name
    }

    /// Where the grid's settings are kept: the library's own grid by its ID, the rest beside it.
    /// All of a library's genres share theirs, as do its studios, as in Wholphin.
    private var settingsPage: String? {
        switch scope {
        case .titles: nil
        case .collections: "collections"
        case .genre: "genres"
        case .studio: "studios"
        }
    }

    /// A genre's page can't be narrowed to other genres, nor a studio's to other studios.
    private var filterKinds: [LibraryFilter.Kind] {
        switch scope {
        case .titles, .collections: library.filterKinds
        case .genre: library.filterKinds.filter { $0 != .genres }
        case .studio: library.filterKinds.filter { $0 != .studios }
        }
    }

    /// Posters for collections and the genre and studio pages, as in Wholphin.
    private var defaultViewOptions: GridViewOptions {
        scope == .titles ? .defaults(for: library.kind) : .defaults(for: .collections)
    }

    private var emptyMessage: String {
        if settings?.filter.isEmpty == false {
            return "Nothing here matches the filters."
        }
        return switch scope {
        case .collections: "No collections hold titles from \(library.name)."
        default: "There's nothing in \(heading) yet."
        }
    }

    private var query: LibraryQuery? {
        settings.map { LibraryQuery(library: library, sort: $0.sort, filter: $0.filter, scope: scope) }
    }

    private var viewOptions: GridViewOptions {
        settings?.view ?? defaultViewOptions
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
        let pager = LibraryPager(loader: loader(for: query))
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

    private func loader(for query: LibraryQuery) -> LibraryPager.Loader {
        #if DEBUG
            if query.scope == .collections, MockCollections.isOn {
                return MockCollections.loader
            }
        #endif
        let session = browse.session
        return { startIndex, limit, includeTotalCount in
            try await session.libraryItems(
                query,
                startIndex: startIndex,
                limit: limit,
                includeTotalCount: includeTotalCount,
            )
        }
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
        var updated = settings ?? browse.libraryPreferences.settings(for: library, page: settingsPage)
        change(&updated)
        settings = updated
        browse.libraryPreferences.save(updated, for: library, page: settingsPage)
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
