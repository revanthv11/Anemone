import SwiftUI

/// Settings › Playback: a page for each part of playback, each in its own file in this folder.
struct PlaybackSettingsPage: View {
    var body: some View {
        List {
            // One `NavigationLink` per page goes here, such as Autoplay or Skip Segments.
            Text("Playback settings arrive later in Phase 3.")
                .foregroundStyle(.secondary)
                // Gives focus somewhere to rest, so Menu goes back to Settings.
                .focusable()
        }
        .navigationTitle("Playback")
    }
}
