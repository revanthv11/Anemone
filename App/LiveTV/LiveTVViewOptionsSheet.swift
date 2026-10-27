import AnemoneCore
import AnemoneUI
import SwiftUI

/// Wholphin's Live TV view options (`LiveTvViewOptionsDialog`), kept on this device.
struct LiveTVViewOptionsSheet: View {
    @AppStorage(Preferences.liveTVShowsDetails) private var showsDetails
    @AppStorage(Preferences.liveTVFavoriteChannelsFirst) private var favoritesFirst
    @AppStorage(Preferences.liveTVRecentlyWatchedFirst) private var recentlyWatchedFirst
    @AppStorage(Preferences.liveTVColorCodesPrograms) private var colorCodes

    var body: some View {
        NavigationStack {
            Form {
                Toggle("Show Details", isOn: $showsDetails)
                    .accessibilityIdentifier("livetv.options.details")
                Toggle("Favorite Channels at Beginning", isOn: $favoritesFirst)
                    .accessibilityIdentifier("livetv.options.favoritesFirst")
                Toggle("Sort Channels by Recently Watched", isOn: $recentlyWatchedFirst)
                    .accessibilityIdentifier("livetv.options.recentlyWatched")
                Toggle("Color Code Programs", isOn: $colorCodes)
                    .accessibilityIdentifier("livetv.options.colorCode")
            }
            .navigationTitle("View Options")
        }
        .frame(width: 1000)
    }
}
