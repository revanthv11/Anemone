import AnemoneCore
import AnemonePlayback
import AnemoneUI
import SwiftUI

/// Settings › Playback › Autoplay: Wholphin's Next Up settings. When Up Next shows, whether it
/// counts down to the next episode and for how long, and when to ask "Still watching?".
struct AutoplaySettingsPage: View {
    @AppStorage(Preferences.autoPlayNext) private var autoPlayNext
    @AppStorage(Preferences.autoPlayNextDelaySeconds) private var countdown
    @AppStorage(Preferences.showNextUpWhen) private var timing
    @AppStorage(Preferences.passOutProtectionCount) private var passOutCount

    var body: some View {
        List {
            Section {
                Picker("Show Up Next", selection: $timing) {
                    Text("At the end").tag(UpNextTiming.endOfPlayback)
                    Text("During the credits").tag(UpNextTiming.duringCredits)
                }
                .accessibilityIdentifier("autoplay.timing")
            } footer: {
                Text("During the credits needs the server to know where they start; otherwise it shows at the end.")
            }
            Section {
                Toggle("Autoplay next", isOn: $autoPlayNext)
                    .accessibilityIdentifier("autoplay.enabled")
                Picker("Countdown", selection: $countdown) {
                    ForEach(Self.countdowns, id: \.self) { seconds in
                        Text(seconds == 0 ? "Immediate" : "\(seconds) seconds").tag(seconds)
                    }
                }
                .disabled(!autoPlayNext)
                .accessibilityIdentifier("autoplay.countdown")
            }
            Section {
                Picker("Ask \"Still watching?\"", selection: $passOutCount) {
                    ForEach(Self.passOutCounts, id: \.self) { count in
                        Text(Self.passOutText(count)).tag(count)
                    }
                }
                .disabled(!autoPlayNext)
                .accessibilityIdentifier("autoplay.stillWatching")
            } footer: {
                Text("Asks once this many videos in a row have played on their own, with no press on the remote, "
                    + "and stops playback when nobody answers.")
            }
        }
        .navigationTitle("Autoplay")
    }

    /// Wholphin's slider: 0 to 60 seconds in steps of 5.
    private static let countdowns = Array(stride(from: 0, through: 60, by: 5))
    private static let passOutCounts = Array(0 ... 5)

    private static func passOutText(_ count: Int) -> String {
        switch count {
        case 0: "Never"
        case 1: "After 1 autoplay"
        default: "After \(count) autoplays"
        }
    }
}
