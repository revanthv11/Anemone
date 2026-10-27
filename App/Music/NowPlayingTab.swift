import AnemonePlayback
import SwiftUI

/// The sidebar's Now Playing entry, which Wholphin's drawer shows at its top while music plays
/// (`NavDrawerService`): it opens the Now Playing page. Like Wholphin's, it goes when the music
/// stops, or once it has been paused or finished for two hours (`MusicPlayer.offersNowPlaying`).
struct NowPlayingTab: @MainActor TabContent {
    @Binding var selection: SignedInView.Destination

    @Environment(MusicPlayer.self) private var player

    var body: some TabContent<SignedInView.Destination> {
        // Kept while it's chosen, so the page can hand the choice to Home once the music stops.
        if player.offersNowPlaying || selection == .nowPlaying {
            Tab("Now Playing", systemImage: "waveform", value: SignedInView.Destination.nowPlaying) {
                // In a stack of its own, like every other tab's page: without one, choosing it from
                // a page pushed in another tab left that page on screen over it.
                NavigationStack {
                    NowPlayingPage {
                        selection = .home
                    }
                }
            }
        }
    }
}
