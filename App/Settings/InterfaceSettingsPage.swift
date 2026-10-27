import AnemoneCore
import AnemonePlayback
import AnemoneUI
import SwiftUI

/// Settings › Interface: Wholphin's theme music and photo slideshow settings, with its names
/// and defaults. The slideshow's time offers Wholphin's 1 to 30 seconds as a few steps, since
/// tvOS has no slider.
struct InterfaceSettingsPage: View {
    @AppStorage(Preferences.playThemeSongs) private var themeVolume
    @AppStorage(Preferences.slideshowDuration) private var slideshowDuration
    @AppStorage(Preferences.slideshowPlayVideos) private var slideshowPlaysVideos

    private static let durations = [1, 2, 3, 5, 8, 10, 15, 20, 30]

    var body: some View {
        List {
            Section {
                Picker("Play theme music", selection: $themeVolume) {
                    ForEach(ThemeMusicVolume.allCases, id: \.self) { volume in
                        Text(volume.title).tag(volume)
                    }
                }
                .accessibilityIdentifier("settings.themeMusic")
            } header: {
                Text("Theme music")
            } footer: {
                Text("Plays on the pages of movies, shows and collections that have a theme song on the server.")
            }
            Section("Photos") {
                Picker("Slideshow duration", selection: $slideshowDuration) {
                    ForEach(Self.durations, id: \.self) { seconds in
                        Text("\(seconds) seconds").tag(seconds * 1000)
                    }
                    // A time set elsewhere, kept as it is.
                    if !Self.durations.contains(slideshowDuration / 1000) || slideshowDuration % 1000 != 0 {
                        Text(Self.label(milliseconds: slideshowDuration)).tag(slideshowDuration)
                    }
                }
                .accessibilityIdentifier("settings.slideshowDuration")
                Toggle("Play videos during slideshow", isOn: $slideshowPlaysVideos)
                    .accessibilityIdentifier("settings.slideshowPlayVideos")
            }
        }
        .pickerStyle(.navigationLink)
        .navigationTitle("Interface")
    }

    private static func label(milliseconds: Int) -> String {
        let seconds = (Double(milliseconds) / 1000).formatted(.number.precision(.fractionLength(0 ... 2)))
        return String(localized: "\(seconds) seconds")
    }
}

private extension ThemeMusicVolume {
    /// Wholphin's names.
    var title: String {
        switch self {
        case .disabled: String(localized: "Disabled")
        case .lowest: String(localized: "Lowest")
        case .low: String(localized: "Low")
        case .medium: String(localized: "Medium")
        case .high: String(localized: "High")
        case .highest: String(localized: "Full")
        }
    }
}
