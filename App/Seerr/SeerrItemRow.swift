import AnemoneJellyfin
import SwiftUI
#if ANEMONE_SEERR
    import AnemoneSeerr
#endif

/// Wholphin's Discover row on movie, series and person pages: titles like this one, or the
/// person's movies and series, found through Seerr, which can be requested. Shows nothing when
/// no Seerr server is connected, and in builds without `ANEMONE_SEERR`, so each page adds it in
/// one line.
struct SeerrItemRow: View {
    let item: ItemDetails
    let focus: FocusState<ItemFocus?>.Binding
    let memory: RowMemory

    var body: some View {
        #if ANEMONE_SEERR
            SeerrSimilarRow(item: item, focus: focus, memory: memory)
        #endif
    }
}

extension View {
    /// Opens Seerr's title pages pushed on `stack`, which the Discover row on item pages links to.
    /// `itemPages(in:)` adds it, so each stack declares it once, at its root; nothing in builds
    /// without `ANEMONE_SEERR`.
    @ViewBuilder
    func seerrPages(in stack: PageStack) -> some View {
        #if ANEMONE_SEERR
            discoverPages(in: stack)
        #else
            self
        #endif
    }
}

#if ANEMONE_SEERR
    private struct SeerrSimilarRow: View {
        let item: ItemDetails
        let focus: FocusState<ItemFocus?>.Binding
        let memory: RowMemory

        @Environment(SeerrModel.self) private var seerr: SeerrModel?
        @State private var found: [DiscoverItem] = []

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                if !found.isEmpty {
                    // Wholphin's title for the row.
                    DiscoverItemsRow(id: "discover", title: "Discover", items: found, focus: focus, memory: memory)
                }
            }
            .task(id: Lookup(itemID: item.id, tmdbID: item.tmdbID, server: seerr?.connection?.serverURL)) {
                await load()
            }
        }

        private struct Lookup: Equatable {
            let itemID: String
            let tmdbID: Int?
            let server: URL?
        }

        /// As Wholphin's `SeerrService.similar`: by the item's TMDB ID, which the page's item came
        /// with, similar movies for a movie, similar series for a series, and a person's credits.
        /// Without a connection or a TMDB ID, or when Seerr fails, there's no row.
        private func load() async {
            guard let connection = seerr?.connection, let kind = item.seerrKind, let tmdbID = item.tmdbID else {
                found = []
                return
            }
            let items = try? await connection.similar(to: tmdbID, kind: kind)
            guard !Task.isCancelled else { return }
            found = items ?? []
        }
    }

    private extension ItemDetails {
        var seerrKind: SeerrMediaKind? {
            switch item.kind {
            case .movie: .movie
            case .series: .series
            case .person: .person
            default: nil
            }
        }
    }
#endif
