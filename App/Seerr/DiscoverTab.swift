#if ANEMONE_SEERR
    import AnemoneSeerr
    import AnemoneUI
    import SwiftUI

    /// The Discover tab, Wholphin's `DiscoverPage`: Seerr's suggestions and the user's requests,
    /// with search a page away, and its own navigation.
    ///
    /// Unlike Wholphin, which only lists Discover in its drawer once Seerr is connected, the tab
    /// is always there in builds with Seerr, and says how to set a server up until one is.
    struct DiscoverTab: View {
        @Environment(SeerrModel.self) private var seerr: SeerrModel?
        @State private var stack = PageStack()

        var body: some View {
            NavigationStack(path: $stack.path) {
                content
                    // The tab's root, which `itemPages(in:)` doesn't reach.
                    .environment(\.pageStack, stack)
                    // Opens Seerr's title pages too.
                    .itemPages(in: stack)
                    .navigationDestination(for: DiscoverSearchRoute.self) { _ in
                        DiscoverSearchPage()
                            .environment(\.pageStack, stack)
                    }
            }
        }

        @ViewBuilder
        private var content: some View {
            switch seerr?.status {
            case nil:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .notConfigured:
                PageMessage(
                    message: "Set up a Seerr server in Settings › Seerr to discover and request movies and shows.",
                )
                .accessibilityIdentifier("discover.notConfigured")
            case let .failed(failure):
                PageMessage(message: "Couldn't sign in to Seerr at \(failure.address). \(failure.reason)")
                    .accessibilityIdentifier("discover.failed")
            case let .connected(connection, _):
                DiscoverSections(connection: connection)
            }
        }
    }

    /// Opens the Discover search page.
    struct DiscoverSearchRoute: Hashable {}

    /// Discover and Requests, as two of Wholphin's tabs, and a button for its search tab.
    private struct DiscoverSections: View {
        enum Section: Hashable {
            case discover
            case requests
        }

        let connection: SeerrConnection
        @State private var section = Section.discover

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 40) {
                    Picker("Section", selection: $section) {
                        Text("Discover").tag(Section.discover)
                        Text("Requests").tag(Section.requests)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 700)
                    .accessibilityIdentifier("discover.section")
                    NavigationLink(value: DiscoverSearchRoute()) {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .accessibilityIdentifier("discover.search")
                }
                .padding(.horizontal, ItemLayout.horizontalInset)
                .focusSection()
                switch section {
                case .discover:
                    DiscoverHome(connection: connection)
                case .requests:
                    DiscoverRequestsPage(connection: connection)
                }
            }
        }
    }

    /// Wholphin's `SeerrDiscoverPage`: a header for the focused title over its backdrop, then a
    /// row each of trending titles, movies, upcoming movies, series and upcoming series.
    private struct DiscoverHome: View {
        let connection: SeerrConnection

        @FocusState private var focus: ItemFocus?
        @State private var memory = RowMemory()
        @State private var rows: [DiscoverRow: [DiscoverItem]] = [:]
        @State private var hasLoaded = false
        @State private var focused: DiscoverItem?

        var body: some View {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: ItemLayout.sectionSpacing) {
                    DiscoverHeader(item: focused)
                    ForEach(DiscoverRow.allCases, id: \.self) { row in
                        if let items = rows[row], !items.isEmpty {
                            DiscoverItemsRow(
                                id: row.rawValue,
                                title: row.title,
                                items: items,
                                focus: $focus,
                                memory: memory,
                            )
                        }
                    }
                    if hasLoaded, rows.values.allSatisfy(\.isEmpty) {
                        PageMessage(message: "Seerr didn't suggest anything. Check that it's running, then try again.")
                    }
                }
                .padding(.horizontal, ItemLayout.horizontalInset)
                .padding(.bottom, ItemLayout.focusPadding)
            }
            .scrollClipDisabled()
            .background {
                BackdropImage(url: focused?.backdropURL)
                    .ignoresSafeArea()
            }
            .onChange(of: focus) { _, focus in
                memory.note(focus)
                if case let .card(row, id) = focus, let row = DiscoverRow(rawValue: row) {
                    focused = rows[row]?.first { $0.id == id }
                }
            }
            // Again after Back, so a title just requested shows as requested.
            .pageTask(id: connection.serverURL) {
                await load()
            }
        }

        /// Each row at once, as Wholphin's view model; a row that fails is left out.
        private func load() async {
            let loaded = await withTaskGroup(of: (DiscoverRow, [DiscoverItem]?).self) { group in
                for row in DiscoverRow.allCases {
                    group.addTask { await (row, try? connection.discover(row)) }
                }
                var loaded: [DiscoverRow: [DiscoverItem]] = [:]
                for await (row, items) in group {
                    loaded[row] = items ?? rows[row]
                }
                return loaded
            }
            guard !Task.isCancelled else { return }
            rows = loaded
            hasLoaded = true
        }
    }

    /// The focused title's name, year, availability and overview, like Wholphin's
    /// `HomePageHeader` on its Discover page. Keeps its height, so the rows don't move.
    private struct DiscoverHeader: View {
        let item: DiscoverItem?

        @Environment(\.theme) private var theme

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                if let item {
                    Text(item.title)
                        .font(.title.bold())
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    Text(item.cardSubtitle)
                        .font(.callout)
                    if let overview = item.overview {
                        Text(overview)
                            .font(.callout)
                            .lineLimit(3)
                    }
                }
            }
            .foregroundStyle(theme.onBackground)
            .frame(maxWidth: ItemLayout.textWidth, minHeight: 220, maxHeight: 220, alignment: .topLeading)
            .padding(.top, 40)
        }
    }

    /// Wholphin's `SeerrRequestsPage`: the requests the user may see, with their status, read a
    /// page at a time as focus nears the end.
    private struct DiscoverRequestsPage: View {
        let connection: SeerrConnection

        @FocusState private var focus: ItemFocus?
        @State private var list = SeerrRequestList()
        @State private var problem: String?

        var body: some View {
            Group {
                if let requests = list.items, requests.isEmpty {
                    PageMessage(message: "No requests yet.")
                } else if let requests = list.items {
                    ScrollView(.vertical) {
                        DiscoverGrid(
                            entries: requests.map {
                                DiscoverGrid.Entry(id: "\($0.id)", item: $0.item, subtitle: $0.request.status.label)
                            },
                            focus: $focus,
                        )
                        .padding(.horizontal, ItemLayout.horizontalInset)
                    }
                    .scrollClipDisabled()
                } else if let problem {
                    PageMessage(message: problem)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .pageTask(id: connection.serverURL) {
                do {
                    try await list.reload(from: connection)
                } catch {
                    if !Task.isCancelled, list.items == nil {
                        problem = "Couldn't load your requests. \(error.seerrReason)"
                    }
                }
            }
            .onChange(of: focus) { _, focus in
                guard case let .card(_, item)? = focus, let id = Int(item) else { return }
                // Not tied to the focused card, so moving on doesn't cancel it; a failure is
                // tried again when focus moves.
                Task {
                    try? await list.readMore(near: id, from: connection)
                }
            }
        }
    }

    /// Wholphin's `DiscoverSearchPage`: movies and series on Seerr, searched as the user types.
    struct DiscoverSearchPage: View {
        @Environment(SeerrModel.self) private var seerr: SeerrModel?
        @Environment(\.theme) private var theme
        @FocusState private var focus: ItemFocus?
        @State private var query = ""
        @State private var results: [DiscoverItem]?
        @State private var problem: String?

        var body: some View {
            ScrollView(.vertical) {
                VStack(alignment: .leading) {
                    if let results, results.isEmpty {
                        Text("Nothing found for “\(query)”.")
                            .foregroundStyle(theme.secondaryText)
                    } else if let results {
                        DiscoverGrid(entries: results.map { .init(id: $0.id, item: $0) }, focus: $focus)
                    } else if let problem {
                        Text(problem)
                            .foregroundStyle(theme.secondaryText)
                    }
                }
                .padding(.horizontal, ItemLayout.horizontalInset)
                .padding(.bottom, ItemLayout.focusPadding)
            }
            .scrollClipDisabled()
            .searchable(text: $query, prompt: "Movies and shows to request")
            .task(id: query) {
                await search(query)
            }
        }

        /// 750 ms after typing pauses, as in Wholphin.
        private func search(_ query: String) async {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let connection = seerr?.connection else {
                results = nil
                problem = nil
                return
            }
            try? await Task.sleep(for: .milliseconds(750))
            guard !Task.isCancelled else { return }
            do {
                let found = try await connection.search(trimmed)
                guard !Task.isCancelled else { return }
                results = found
                problem = nil
            } catch {
                guard !Task.isCancelled else { return }
                results = nil
                problem = "Couldn't search Seerr. \(error.seerrReason)"
            }
        }
    }

    extension SeerrFailure {
        var reason: String {
            error.seerrReason
        }
    }

    extension Error {
        /// One sentence on why a Seerr request failed.
        var seerrReason: String {
            switch self as? SeerrError {
            case .invalidCredentials:
                "Seerr didn't accept the username and password or API key."
            case .forbidden:
                "Seerr says this account isn't allowed to do that."
            case .invalidAddress:
                "That isn't a server address."
            case .unexpectedResponse:
                "No Seerr server answered at that address."
            case let .status(code):
                "Seerr answered with error \(code)."
            case nil:
                "Check that the Seerr server is running, then try again."
            }
        }
    }
#endif
