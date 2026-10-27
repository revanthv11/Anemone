#if DEBUG
    import AnemoneCore
    import AnemoneJellyfin

    /// Made-up home data for checking features the demo server can't show, like the
    /// `-homeSpike` launch argument in `RootView`.
    enum HomeDebugData {
        /// What "Import from Wholphin" finds with `-homeMockWholphin YES`: Wholphin's split
        /// watching rows, then genres and favourites, built from the user's own libraries.
        static func wholphinSettings(for libraries: [Library]) -> HomePageSettings {
            var rows = [HomeRowConfig(.nextUp), HomeRowConfig(.continueWatching)]
            if let movies = libraries.first(where: { $0.kind == .movies }) ?? libraries.first {
                rows.append(HomeRowConfig(.genres(parentID: movies.id)))
                rows.append(HomeRowConfig(.recentlyReleased(parentID: movies.id)))
            }
            rows.append(HomeRowConfig(.favorite(itemKind: "Movie")))
            return HomePageSettings(rows: rows)
        }

        /// Live TV rows with `-homeMockLiveTV YES`, until the Live TV feature provides real ones.
        struct MockLiveTV: HomeLiveTVSource {
            func recordingsInProgress(limit: Int) async throws -> [MediaItem] {
                items("Recording", count: min(limit, 2), kind: .video)
            }

            func programsOnNow(limit: Int) async throws -> [MediaItem] {
                items("On now", count: min(limit, 6), kind: .other)
            }

            func channels(limit: Int) async throws -> [MediaItem] {
                items("Channel", count: min(limit, 8), kind: .other)
            }

            private func items(_ name: String, count: Int, kind: MediaItem.Kind) -> [MediaItem] {
                (1 ... max(count, 1)).map { number in
                    MediaItem(
                        id: "mock-\(name.lowercased().replacingOccurrences(of: " ", with: "-"))-\(number)",
                        name: "\(name) \(number)",
                        kind: kind,
                        overview: "Made-up Live TV data for checking Home's Live TV rows.",
                    )
                }
            }
        }
    }
#endif
