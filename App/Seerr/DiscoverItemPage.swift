#if ANEMONE_SEERR
    import AnemoneJellyfin
    import AnemoneSeerr
    import AnemoneUI
    import SwiftUI

    /// A movie's or series' page on Seerr: Wholphin's `DiscoverMovieDetails` and
    /// `DiscoverSeriesDetails`, with its details, a Request button (or Go To once the server has
    /// it), Cancel for a request the user may withdraw, and rows of similar and recommended titles.
    ///
    /// Not yet: the cast, trailers, ratings from Rotten Tomatoes, and the advanced request options
    /// (server, quality profile and folder) Wholphin offers users allowed to choose them.
    struct DiscoverItemPage: View {
        let item: DiscoverItem

        @Environment(SeerrModel.self) private var seerr: SeerrModel?
        @FocusState private var focus: ItemFocus?
        @State private var memory = RowMemory()
        @State private var details: DiscoverDetails?
        @State private var similar: [DiscoverItem] = []
        @State private var recommended: [DiscoverItem] = []
        @State private var problem: String?
        @State private var alert: ItemAlert?
        @State private var isChoosingQuality = false
        @State private var isChoosingSeasons = false
        @State private var isWorking = false

        var body: some View {
            Group {
                if let connection = seerr?.connection, let details {
                    page(details, connection: connection)
                } else if let problem {
                    PageMessage(message: problem)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background {
                BackdropImage(url: details?.item.backdropURL ?? item.backdropURL)
                    .ignoresSafeArea()
            }
            .itemAlert($alert)
            .task(id: item.id) {
                await load()
            }
        }

        private func page(_ details: DiscoverDetails, connection: SeerrConnection) -> some View {
            ScrollViewReader { scroller in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: ItemLayout.sectionSpacing) {
                        header(details)
                        buttons(details, connection: connection)
                        rows
                    }
                    .padding(.horizontal, ItemLayout.horizontalInset)
                    .padding(.top, ItemLayout.topInset)
                    .padding(.bottom, ItemLayout.focusPadding)
                    .id(ItemLayout.headerID)
                }
                .onChange(of: focus) { _, focus in
                    memory.note(focus)
                    if focus?.isInHeader == true {
                        withAnimation { scroller.scrollTo(ItemLayout.headerID, anchor: .top) }
                    }
                }
            }
            .initialFocus($focus, .action(.play))
            .confirmationDialog(details.item.title, isPresented: $isChoosingQuality) {
                Button("Request") {
                    Task { await requestMovie(is4K: false) }
                }
                Button("Request in 4K") {
                    Task { await requestMovie(is4K: true) }
                }
            }
            .sheet(isPresented: $isChoosingSeasons) {
                RequestSeasonsSheet(
                    details: details,
                    canRequest: connection.canRequestSeries,
                    canRequest4K: connection.canRequest4KSeries,
                ) { seasons, is4K in
                    isChoosingSeasons = false
                    Task { await requestSeries(seasons, is4K: is4K) }
                }
            }
        }

        @ViewBuilder
        private var rows: some View {
            if !similar.isEmpty {
                DiscoverItemsRow(id: "similar", title: "Similar", items: similar, focus: $focus, memory: memory)
            }
            if !recommended.isEmpty {
                DiscoverItemsRow(
                    id: "recommended",
                    title: "Recommended",
                    items: recommended,
                    focus: $focus,
                    memory: memory,
                )
            }
        }

        private func header(_ details: DiscoverDetails) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(details.item.title)
                    .font(.title.bold())
                    .lineLimit(2)
                    .accessibilityIdentifier("detail.title")
                Text(quickDetails(details))
                    .font(.callout)
                    .lineLimit(1)
                if !details.genres.isEmpty {
                    NameList(names: details.genres)
                }
                if let tagline = details.tagline {
                    Text(tagline)
                        .font(.callout)
                        .italic()
                }
                if let overview = details.item.overview, !overview.isEmpty {
                    OverviewButton(title: details.item.title, overview: overview)
                        .focused($focus, equals: .overview)
                }
            }
            .frame(maxWidth: ItemLayout.textWidth, alignment: .leading)
        }

        /// The first button follows Wholphin's `ExpandableDiscoverButtons`: Request, Requested,
        /// Go To or Unavailable, by how much of the title the server has.
        private func buttons(_ details: DiscoverDetails, connection: SeerrConnection) -> some View {
            HStack(spacing: 24) {
                switch details.item.availability {
                case .unknown:
                    requestButton(details, connection: connection)
                        .focused($focus, equals: .action(.play))
                case .pending, .processing:
                    ActionButton(title: details.item.availability.label ?? "Requested", systemImage: "clock") {}
                        .focused($focus, equals: .action(.play))
                        .accessibilityIdentifier("action.requested")
                case .partiallyAvailable, .available:
                    goToButton(details)
                        .focused($focus, equals: .action(.play))
                    if details.item.availability == .partiallyAvailable, details.item.kind == .series {
                        requestButton(details, connection: connection)
                    }
                case .blocklisted, .deleted:
                    ActionButton(title: "Unavailable", systemImage: "xmark.circle") {}
                        .focused($focus, equals: .action(.play))
                        .disabled(true)
                }
                if let request = connection.requestToCancel(in: details) {
                    ActionButton(title: "Cancel Request", systemImage: "trash") {
                        Task { await cancel(request) }
                    }
                    .accessibilityIdentifier("action.cancelRequest")
                }
            }
            .disabled(isWorking)
            .padding(.vertical, 20)
            .focusSection()
        }

        @ViewBuilder
        private func requestButton(_ details: DiscoverDetails, connection: SeerrConnection) -> some View {
            let canRequest = details.item.kind == .movie
                ? connection.canRequestMovies || connection.canRequest4KMovies
                : connection.canRequestSeries || connection.canRequest4KSeries
            ActionButton(title: "Request", systemImage: "arrow.down.circle") {
                request(details, connection: connection)
            }
            .disabled(!canRequest)
            .accessibilityIdentifier("action.request")
        }

        @ViewBuilder
        private func goToButton(_ details: DiscoverDetails) -> some View {
            if let jellyfinItem = details.item.jellyfinItem {
                NavigationLink(value: jellyfinItem) {
                    GoToLabel()
                }
                .accessibilityLabel("Go To")
                .accessibilityIdentifier("action.goTo")
            } else {
                // Wholphin says the Jellyfin ID is missing; this says what to do.
                ActionButton(title: "Go To", systemImage: "play.fill") {
                    alert = .failed("Seerr says \(details.item.title) is on the server, but didn't say where.")
                }
            }
        }

        private func quickDetails(_ details: DiscoverDetails) -> String {
            var parts: [String] = []
            if let year = details.item.year {
                parts.append(String(year))
            }
            if let runtime = details.runtime, runtime > 0 {
                parts.append(runtime >= 60 ? "\(runtime / 60)h \(runtime % 60)m" : "\(runtime)m")
            }
            if let rating = details.rating, rating > 0 {
                parts.append(String(format: "★ %.1f", rating))
            }
            if let label = details.item.availability.label {
                parts.append(label)
            }
            return parts.joined(separator: " · ")
        }

        // MARK: Loading and requesting

        private func load() async {
            guard let connection = seerr?.connection else {
                problem = "Seerr isn't connected. Check Settings › Seerr."
                return
            }
            async let similar = try? connection.similar(to: item.tmdbID, kind: item.kind)
            async let recommended = try? connection.recommendations(for: item.tmdbID, kind: item.kind)
            await reload(connection)
            self.similar = await similar ?? []
            self.recommended = await recommended ?? []
        }

        private func reload(_ connection: SeerrConnection) async {
            do {
                details = try await item.kind == .movie ? connection.movie(item.tmdbID) : connection.series(item.tmdbID)
                problem = nil
            } catch {
                if !Task.isCancelled, details == nil {
                    problem = "Couldn't load \(item.title) from Seerr. \(error.seerrReason)"
                }
            }
        }

        /// A movie asks which quality when the user may request both, as Wholphin's
        /// `RequestMovieDialog`; a series lists its seasons.
        private func request(_ details: DiscoverDetails, connection: SeerrConnection) {
            if details.item.kind == .series {
                isChoosingSeasons = true
            } else if connection.canRequestMovies, connection.canRequest4KMovies {
                isChoosingQuality = true
            } else {
                Task { await requestMovie(is4K: !connection.canRequestMovies) }
            }
        }

        private func requestMovie(is4K: Bool) async {
            await perform("request \(item.title)") { connection in
                try await connection.requestMovie(item.tmdbID, is4K: is4K)
            }
        }

        private func requestSeries(_ seasons: [Int], is4K: Bool) async {
            guard let details, !seasons.isEmpty else { return }
            await perform("request \(item.title)") { connection in
                try await connection.requestSeries(details, seasons: seasons, is4K: is4K)
            }
        }

        private func cancel(_ request: SeerrRequest) async {
            await perform("cancel the request") { connection in
                try await connection.cancelRequest(request)
            }
        }

        /// Runs a change on Seerr, then shows the title as it is now, as Wholphin reloads it.
        private func perform(_ what: String, _ change: (SeerrConnection) async throws -> Void) async {
            guard let connection = seerr?.connection else { return }
            isWorking = true
            defer { isWorking = false }
            do {
                try await change(connection)
            } catch {
                alert = .failed("Couldn't \(what). \(error.seerrReason)")
            }
            await reload(connection)
            focus = .action(.play)
        }
    }

    /// Go To's icon, showing its title while focused like the other buttons (`ActionButton`).
    private struct GoToLabel: View {
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: "play.fill")
                if isFocused {
                    Text("Go To")
                        .fixedSize()
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: isFocused)
        }
    }
#endif
