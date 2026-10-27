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
        /// The button that asked for a request, for focus to go back to once it's made.
        @State private var requestedFrom = ItemAction.play

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
            // Back to the button it came from once the sheet has gone, since focus can't move
            // while it's up, and that button may have changed from Request to Requested.
            .sheet(isPresented: $isChoosingSeasons, onDismiss: { focus = focusAfterRequest }, content: {
                RequestSeasonsSheet(
                    details: details,
                    canRequest: connection.canRequestSeries,
                    canRequest4K: connection.canRequest4KSeries,
                ) { seasons, is4K in
                    isChoosingSeasons = false
                    Task { await requestSeries(seasons, is4K: is4K) }
                }
            })
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
            DiscoverItemHeader(details: details) {
                if let overview = details.item.overview, !overview.isEmpty {
                    OverviewButton(title: details.item.title, overview: overview)
                        .focused($focus, equals: .overview)
                }
            }
        }

        /// The first button follows Wholphin's `ExpandableDiscoverButtons`: Request, Requested,
        /// Go To or Unavailable, by how much of the title the server has.
        private func buttons(_ details: DiscoverDetails, connection: SeerrConnection) -> some View {
            HStack(spacing: 24) {
                switch details.item.availability {
                case .unknown:
                    requestButton(details, connection: connection, as: .play)
                case .pending, .processing:
                    requestedButton(details, connection: connection)
                        .focused($focus, equals: .action(.play))
                case .partiallyAvailable, .available:
                    goToButton(details)
                        .focused($focus, equals: .action(.play))
                    if details.offersMoreSeasons {
                        requestButton(details, connection: connection, as: .request)
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

        /// - Parameter action: which button it is, for focus.
        @ViewBuilder
        private func requestButton(
            _ details: DiscoverDetails,
            connection: SeerrConnection,
            as action: ItemAction,
        ) -> some View {
            let canRequest = details.item.kind == .movie
                ? connection.canRequestMovies || connection.canRequest4KMovies
                : connection.canRequestSeries || connection.canRequest4KSeries
            ActionButton(title: "Request", systemImage: "arrow.down.circle") {
                requestedFrom = action
                request(details, connection: connection)
            }
            .disabled(!canRequest)
            .focused($focus, equals: .action(action))
            .accessibilityIdentifier("action.request")
        }

        /// Requested, while the title is pending or on its way. On a series it opens the seasons
        /// again, as Wholphin's `DiscoverSeriesDetails` passes `pendingOnClick = requestOnClick`,
        /// so the user can ask for more seasons or change the ones still pending. A movie has
        /// nothing more to ask for, so there it only says where the request stands.
        private func requestedButton(_ details: DiscoverDetails, connection: SeerrConnection) -> some View {
            let canRequestMore = details.item.kind == .series
                && (connection.canRequestSeries || connection.canRequest4KSeries)
            return ActionButton(title: details.item.availability.label ?? "Requested", systemImage: "clock") {
                if canRequestMore {
                    requestedFrom = .play
                    request(details, connection: connection)
                }
            }
            .accessibilityHint(canRequestMore ? "Choose seasons to request" : "")
            .accessibilityIdentifier("action.requested")
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
            requestedFrom = .play
            await perform("cancel the request") { connection in
                try await connection.cancelRequest(request)
            }
        }

        /// Runs a change on Seerr, then shows the title as it is now, as Wholphin reloads it.
        private func perform(_ what: String, _ change: (SeerrConnection) async throws -> Void) async {
            guard let connection = seerr?.connection else { return }
            isWorking = true
            do {
                try await change(connection)
            } catch {
                alert = .failed("Couldn't \(what). \(error.seerrReason)")
            }
            await reload(connection)
            // The buttons take focus again only once they're enabled.
            isWorking = false
            focus = focusAfterRequest
        }

        /// The button that asked for the request, while the page still has it; otherwise the
        /// first.
        private var focusAfterRequest: ItemFocus {
            requestedFrom == .request && details?.offersMoreSeasons == true ? .action(.request) : .action(.play)
        }
    }

    /// The title, its details, genres and tagline, then `overview`, the page's focusable overview.
    private struct DiscoverItemHeader<Overview: View>: View {
        let details: DiscoverDetails
        @ViewBuilder let overview: () -> Overview

        @Environment(\.theme) private var theme

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(details.item.title)
                    .font(.title.bold())
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("detail.title")
                Text(details.quickDetails().joined(separator: " · "))
                    .font(.callout)
                    .lineLimit(1)
                    .accessibilityLabel(details.quickDetails(spoken: true).joined(separator: ", "))
                    .accessibilityIdentifier("detail.quickDetails")
                if !details.genres.isEmpty {
                    NameList(names: details.genres)
                }
                if let tagline = details.tagline {
                    Text(tagline)
                        .font(.callout)
                        .italic()
                }
                overview()
            }
            .foregroundStyle(theme.onBackground)
            .frame(maxWidth: ItemLayout.textWidth, alignment: .leading)
        }
    }

    private extension DiscoverDetails {
        /// A series the server has some of, which can be asked for more of with a second Request
        /// button after Go To.
        var offersMoreSeasons: Bool {
            item.availability == .partiallyAvailable && item.kind == .series
        }

        /// The year, runtime, rating and availability, for one line under the title.
        ///
        /// - Parameter spoken: the parts as VoiceOver reads them, with the runtime in words and
        ///   the rating named, without the star.
        func quickDetails(spoken: Bool = false) -> [String] {
            var parts: [String] = []
            if let year = item.year {
                parts.append(String(year))
            }
            if let runtime, runtime > 0 {
                if spoken {
                    parts.append(Duration.seconds(runtime * 60).spokenLength)
                } else {
                    parts.append(runtime >= 60 ? "\(runtime / 60)h \(runtime % 60)m" : "\(runtime)m")
                }
            }
            if let rating, rating > 0 {
                parts.append(String(format: spoken ? "Community rating %.1f out of 10" : "★ %.1f", rating))
            }
            if let label = item.availability.label {
                parts.append(label)
            }
            return parts
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
