import AnemoneCore
import AnemonePlayback
import AnemoneUI
import SwiftUI

/// Settings › Playback › Player Controls: the system player or Anemone's own overlay, and how the
/// overlay seeks, hides and what it shows. Skip amounts and the hiding delay offer Wholphin's
/// ranges as a few steps, since tvOS has no slider.
struct PlayerControlsSettingsPage: View {
    @AppStorage(Preferences.playerControls) private var controls
    @AppStorage(Preferences.skipForwardMs) private var skipForwardMs
    @AppStorage(Preferences.skipBackMs) private var skipBackMs
    @AppStorage(Preferences.controllerTimeoutMs) private var controllerTimeoutMs
    @AppStorage(Preferences.showDebugInfo) private var showsDebugInfo

    private static let skips = [5, 10, 15, 20, 30, 45, 60, 90, 120, 300]
    private static let timeouts = [2, 3, 5, 8, 10, 15]

    var body: some View {
        List {
            Section {
                Picker("Player controls", selection: $controls) {
                    Text("System").tag(PlayerControls.system)
                    Text("Anemone").tag(PlayerControls.anemone)
                }
                .accessibilityIdentifier("settings.playerControls")
            } header: {
                Text("Controls")
            } footer: {
                Text(footer)
            }
            Section("Anemone's controls") {
                // Each opens its list of choices; inline, tvOS shows them without their titles.
                Picker("Skip forward", selection: $skipForwardMs) {
                    ForEach(Self.skips, id: \.self) { seconds in
                        Text(Self.label(seconds)).tag(seconds * 1000)
                    }
                }
                Picker("Skip back", selection: $skipBackMs) {
                    ForEach(Self.skips, id: \.self) { seconds in
                        Text(Self.label(seconds)).tag(seconds * 1000)
                    }
                }
                Picker("Hide controls after", selection: $controllerTimeoutMs) {
                    ForEach(Self.timeouts, id: \.self) { seconds in
                        Text(Self.label(seconds)).tag(seconds * 1000)
                    }
                }
                Toggle("Show playback debug info", isOn: $showsDebugInfo)
                    .accessibilityIdentifier("settings.showDebugInfo")
            }
            .pickerStyle(.navigationLink)
        }
        .navigationTitle("Player Controls")
    }

    private var footer: String {
        switch controls {
        case .system:
            "Apple TV's own player, with its scrubbing and info panel."
        case .anemone:
            "Wholphin's controls: hold left or right to seek faster, with trickplay thumbnails, chapters and "
                + "the queue."
        }
    }

    private static func label(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds) s" : seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds) s"
    }
}
