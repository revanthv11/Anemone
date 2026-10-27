#if ANEMONE_SEERR
    import AnemoneSeerr
    import SwiftUI

    /// Choosing a series' seasons to request, as Wholphin's `RequestSeasons`: each season with
    /// what the server has of it, the ones that can be asked for ticked, and 4K when the server
    /// and the user allow it.
    struct RequestSeasonsSheet: View {
        let details: DiscoverDetails
        let canRequest: Bool
        let canRequest4K: Bool
        let submit: (_ seasons: [Int], _ is4K: Bool) -> Void

        @Environment(\.dismiss) private var dismiss
        @State private var is4K = false
        @State private var chosen: Set<Int> = []

        var body: some View {
            NavigationStack {
                List {
                    if canRequest, canRequest4K {
                        Toggle("4K", isOn: $is4K)
                            .accessibilityIdentifier("request.4k")
                    }
                    Section("Seasons") {
                        Toggle("All Seasons", isOn: allSeasons)
                            .disabled(requestable.isEmpty)
                            .accessibilityIdentifier("request.allSeasons")
                        ForEach(seasons) { season in
                            Toggle(isOn: binding(for: season)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(season.name ?? "Season \(season.number)")
                                    Text(caption(season))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .disabled(!season.isRequestable)
                            .accessibilityIdentifier("request.season.\(season.number)")
                        }
                    }
                    Section {
                        Button("Request \(chosen.count) Season\(chosen.count == 1 ? "" : "s")") {
                            submit(chosen.sorted(), is4K)
                        }
                        .disabled(chosen.isEmpty)
                        .accessibilityIdentifier("request.submit")
                        Button("Cancel", role: .cancel) {
                            dismiss()
                        }
                    }
                }
                .navigationTitle(details.item.title)
            }
            .onAppear {
                is4K = !canRequest && canRequest4K
                chooseRequested()
            }
            .onChange(of: is4K) {
                chooseRequested()
            }
        }

        /// The seasons at the chosen quality, specials last as Seerr's site lists them.
        private var seasons: [SeerrSeason] {
            let all = is4K ? details.seasons4K : details.seasons
            return all.filter { $0.number > 0 } + all.filter { $0.number == 0 }
        }

        private var requestable: Set<Int> {
            Set(seasons.filter(\.isRequestable).map(\.number))
        }

        /// Starts from the seasons already asked for and still pending, as Wholphin does, so
        /// sending again keeps them in the user's request.
        private func chooseRequested() {
            chosen = Set(seasons.filter { $0.isRequestable && $0.requestStatus == .pending }.map(\.number))
        }

        private var allSeasons: Binding<Bool> {
            Binding {
                !requestable.isEmpty && requestable.isSubset(of: chosen)
            } set: { isOn in
                chosen = isOn ? requestable : []
            }
        }

        /// Seasons that can't be asked for show ticked when the server has them or they're on
        /// their way, as in Wholphin.
        private func binding(for season: SeerrSeason) -> Binding<Bool> {
            Binding {
                chosen.contains(season.number) || (!season.isRequestable && season.isComing)
            } set: { isOn in
                if isOn {
                    chosen.insert(season.number)
                } else {
                    chosen.remove(season.number)
                }
            }
        }

        private func caption(_ season: SeerrSeason) -> String {
            var parts: [String] = []
            if let count = season.episodeCount {
                parts.append("\(count) episode\(count == 1 ? "" : "s")")
            }
            if let label = season.availability.label {
                parts.append(label)
            } else if season.requestStatus != .unknown {
                parts.append(season.requestStatus.label)
            }
            return parts.joined(separator: " · ")
        }
    }

    private extension SeerrSeason {
        /// On the server, or asked for and not turned down.
        var isComing: Bool {
            [.pending, .approved, .completed].contains(requestStatus)
                || availability == .partiallyAvailable || availability == .available
        }
    }
#endif
