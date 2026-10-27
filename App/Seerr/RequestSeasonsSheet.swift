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
                            let name = season.name ?? String(localized: "Season \(season.number)")
                            Toggle(isOn: binding(for: season)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(name)
                                    Text(caption(season).joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            // With pauses where the caption has dots.
                            .accessibilityLabel(([name] + caption(season)).joined(separator: ", "))
                            .disabled(!season.isRequestable)
                            .accessibilityIdentifier("request.season.\(season.number)")
                        }
                    }
                    Section {
                        // One key with plural forms in the String Catalog.
                        Button("Request \(chosen.count) Seasons") {
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

        /// Starts from the seasons of the user's own pending request, as Wholphin does, so sending
        /// again keeps them in it, even those another request also asks for.
        private func chooseRequested() {
            chosen = Set(seasons.filter(\.isInOwnRequest).map(\.number))
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

        /// How many episodes, and what the server has of it, under the season's name.
        private func caption(_ season: SeerrSeason) -> [String] {
            var parts: [String] = []
            if let count = season.episodeCount {
                parts.append(String(localized: "\(count) episodes"))
            }
            if let label = season.availability.label {
                parts.append(label)
            } else if season.requestStatus != .unknown {
                parts.append(season.requestStatus.label)
            }
            return parts
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
