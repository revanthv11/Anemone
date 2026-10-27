import SwiftUI

/// Wholphin's Favorites page (`FavoritesPage`): the user's favourites, a row per type.
struct FavoritesPage: View {
    /// Whether the sidebar shows Favorites. Off until the page has something to show.
    static let isAvailable = false

    var body: some View {
        PlaceholderPage(title: "Favorites", message: "Favorites arrive later in Phase 2.")
    }
}
