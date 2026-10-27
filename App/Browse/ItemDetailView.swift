import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// An item's page. Loads the item, then shows the page for its type, as Wholphin's
/// `DestinationContent` does. Home rows and library grids open this with any `MediaItem`.
struct ItemDetailView: View {
    let item: MediaItem

    @Environment(BrowseModel.self) private var browse
    @State private var details: ItemDetails?
    @State private var problem: String?

    var body: some View {
        Group {
            if let details = Binding($details) {
                ItemPage(details: details)
            } else if let problem {
                PageMessage(message: problem)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background {
            if details == nil {
                BackdropImage(url: browse.imageURL(item.backdropImage, width: ItemLayout.backdropPixelWidth))
                    .ignoresSafeArea()
            }
        }
        // Runs again whenever the page comes back into view, like Wholphin's refresh on resume,
        // so changes made on other pages show.
        .pageTask(id: item.id) {
            await load()
        }
        .themeMusic(for: details)
    }

    private func load() async {
        do {
            details = try await browse.session.itemDetails(id: item.id)
            problem = nil
        } catch {
            let message = browse.problem(with: error, doing: "load \(item.name) from \(browse.server.name)")
            // A failed refresh keeps the page that's already showing.
            if details == nil {
                problem = message
            }
        }
    }
}

extension View {
    /// Opens item pages pushed on `stack`.
    func itemPages(in stack: PageStack) -> some View {
        navigationDestination(for: MediaItem.self) { item in
            ItemDetailView(item: item)
                // Set on each page, because tvOS doesn't pass the stack's own environment on to
                // the pages pushed on it.
                .environment(\.pageStack, stack)
        }
        .seerrPages(in: stack)
    }
}

/// The page for the item's type.
private struct ItemPage: View {
    @Binding var details: ItemDetails

    var body: some View {
        switch details.item.kind {
        case .series:
            SeriesPage(series: $details)
        // Seasons and episodes open the series' season page, as in Wholphin.
        case .season where details.item.episode?.seriesID != nil:
            SeasonPage(
                seriesID: details.item.episode?.seriesID ?? "",
                seasonID: details.id,
                episodeID: nil,
            )
        case .episode where details.item.episode?.seriesID != nil && details.seasonID != nil:
            SeasonPage(
                seriesID: details.item.episode?.seriesID ?? "",
                seasonID: details.seasonID ?? "",
                episodeID: details.id,
            )
        case .collection:
            CollectionPage(collection: $details)
        case .playlist:
            PlaylistPage(playlist: $details)
        case .person:
            PersonPage(person: $details)
        case .musicAlbum, .musicArtist, .audio:
            MusicItemPage(details: $details)
        default:
            MoviePage(item: $details)
        }
    }
}
