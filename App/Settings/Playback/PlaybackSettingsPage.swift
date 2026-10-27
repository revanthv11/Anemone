import SwiftUI

/// Settings › Playback: a page for each part of playback, each in its own file in this folder.
struct PlaybackSettingsPage: View {
    var body: some View {
        List {
            // One `NavigationLink` per page goes here, such as Autoplay or Skip Segments.
            NavigationLink("Skip Segments") {
                SegmentSettingsPage()
            }
            .accessibilityIdentifier("settings.skipSegments")
            NavigationLink("Autoplay") {
                AutoplaySettingsPage()
            }
            .accessibilityIdentifier("settings.playback.autoplay")
            NavigationLink("Audio and Subtitles") {
                AudioSubtitleSettingsPage()
            }
            .accessibilityIdentifier("settings.audioSubtitles")
        }
        .navigationTitle("Playback")
    }
}
