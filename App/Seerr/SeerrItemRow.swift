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

#if ANEMONE_SEERR
    private struct SeerrSimilarRow: View {
        let item: ItemDetails
        let focus: FocusState<ItemFocus?>.Binding
        let memory: RowMemory

        @Environment(SeerrModel.self) private var seerr: SeerrModel?
        @Environment(BrowseModel.self) private var browse
        @Environment(\.pageStack) private var stack
        @State private var found: [DiscoverItem] = []

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                if !found.isEmpty {
                    // Wholphin's title for the row.
                    DiscoverItemsRow(id: "discover", title: "Discover", items: found, focus: focus, memory: memory)
                }
            }
            // Here, since the stacks of other tabs don't open Seerr's pages.
            .discoverPages(in: stack)
            .task(id: Lookup(itemID: item.id, server: seerr?.connection?.serverURL)) {
                await load()
            }
        }

        private struct Lookup: Equatable {
            let itemID: String
            let server: URL?
        }

        /// As Wholphin's `SeerrService.similar`: by the item's TMDB ID, similar movies for a movie,
        /// similar series for a series, and a person's credits. Failures leave the row out.
        private func load() async {
            guard let connection = seerr?.connection, let kind = item.seerrKind else {
                found = []
                return
            }
            let session = browse.session
            let id = item.id
            guard let tmdbID = await browse.optional(attempt { try await session.tmdbID(ofItem: id) }) ?? nil else {
                return
            }
            let items = try? await connection.similar(to: tmdbID, kind: kind)
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
