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
            .accessibilityIdentifier("settings.playback.audioSubtitles")
            NavigationLink("Player Controls", destination: PlayerControlsSettingsPage.init)
                .accessibilityIdentifier("settings.playback.playerControls")
            NavigationLink("Streaming and Display") {
                StreamingSettingsPage()
            }
            .accessibilityIdentifier("settings.playback.streamingAndDisplay")
        }
        .navigationTitle("Playback")
    }
}
