import AnemoneCore
import AnemonePlayback
import SwiftUI

/// Settings › Playback › Subtitle Style: how the text subtitles Anemone draws look, with either
/// player, and a second style for HDR video if the user wants one. The same settings as MPV's in
/// Settings › Playback › Player, which shows them only for MPV.
struct SubtitleStyleSettingsPage: View {
    @AppStorage(Preferences.subtitleStyleSeparateHDR) private var separateHDR

    var body: some View {
        List {
            Section {
                NavigationLink("Subtitle style") {
                    SubtitleStylePage(preference: Preferences.subtitleStyle, title: String(localized: "Subtitle Style"))
                }
                .accessibilityIdentifier("settings.subtitleStyle")
                Toggle("Use a different style for HDR", isOn: $separateHDR)
                    .accessibilityIdentifier("settings.subtitleStyleSeparateHDR")
                if separateHDR {
                    NavigationLink("HDR subtitle style") {
                        SubtitleStylePage(
                            preference: Preferences.hdrSubtitleStyle,
                            title: String(localized: "HDR Subtitle Style"),
                        )
                    }
                    .accessibilityIdentifier("settings.hdrSubtitleStyle")
                }
            } footer: {
                Text("For text subtitles such as SRT. ASS subtitles keep their own styling.")
            }
        }
        .navigationTitle("Subtitle Style")
    }
}
