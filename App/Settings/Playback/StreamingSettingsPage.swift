import AnemoneCore
import AnemonePlayback
import AnemoneUI
import SwiftUI

/// Settings › Playback › Streaming and Display: the streaming limit, skipping back on resume, and
/// how the display follows the video. Wholphin's `MaxBitrate` and `SkipBackOnResume` settings,
/// with its names, choices and defaults; its refresh-rate and resolution switches become tvOS's
/// own Match Content setting. Named apart from Player Controls, which is about the controls.
struct StreamingSettingsPage: View {
    @AppStorage(Preferences.maxBitrate) private var maxBitrate: Int
    @AppStorage(Preferences.skipBackOnResume) private var skipBack: Int

    private static let skipBackChoices = Array(0 ... 10)

    var body: some View {
        List {
            Section {
                NavigationLink {
                    ChoiceList(
                        title: String(localized: "Max Bitrate"),
                        choices: AVPlayerProfile.bitrateChoices,
                        selection: $maxBitrate,
                        label: \.bitrateText,
                    )
                } label: {
                    LabeledContent("Max bitrate", value: maxBitrate.bitrateText)
                }
                .accessibilityIdentifier("settings.maxBitrate")
            } footer: {
                Text("Videos above this are converted to a lower bitrate by the server.")
            }
            Section {
                NavigationLink {
                    ChoiceList(
                        title: String(localized: "Skip Back on Resume"),
                        choices: Self.skipBackChoices,
                        selection: $skipBack,
                        label: Self.skipBackText,
                    )
                } label: {
                    LabeledContent("Skip back when resuming playback", value: Self.skipBackText(skipBack))
                }
                .accessibilityIdentifier("settings.skipBackOnResume")
            } footer: {
                Text("Goes back a little whenever playback resumes after a pause.")
            }
            Section {
                // Gives the list somewhere to rest focus on, so the footer scrolls into view.
                LabeledContent("Match Content", value: matchContentText)
                    .focusable()
                    .accessibilityIdentifier("settings.matchContent")
            } footer: {
                Text("""
                The frame rate and dynamic range follow Match Content in the Apple TV's Settings, \
                under Video and Audio.
                """)
            }
        }
        .navigationTitle("Streaming and Display")
    }

    private var matchContentText: String {
        switch DisplayCriteriaMatching.isMatchingEnabled {
        case true?: String(localized: "On")
        case false?: String(localized: "Off")
        case nil: String(localized: "Unknown")
        }
    }

    private static func skipBackText(_ seconds: Int) -> String {
        seconds == 0 ? String(localized: "Off") : String(localized: "\(seconds) s")
    }
}

/// One setting's choices on a page of their own, as Wholphin lists them in a dialog; choosing
/// goes back.
private struct ChoiceList<Value: Hashable>: View {
    let title: String
    let choices: [Value]
    @Binding var selection: Value
    let label: (Value) -> String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(choices, id: \.self) { choice in
            Button {
                selection = choice
                dismiss()
            } label: {
                HStack {
                    Text(label(choice))
                    Spacer()
                    if choice == selection {
                        Image(systemName: "checkmark")
                            .accessibilityHidden(true)
                    }
                }
            }
            // The check, for VoiceOver.
            .accessibilityAddTraits(choice == selection ? .isSelected : [])
            .accessibilityIdentifier("settings.choice.\(choice)")
        }
        .navigationTitle(title)
    }
}

extension Int {
    /// A bitrate as Wholphin shows one: "750 kbps", "8 Mbps", "8.5 Mbps".
    var bitrateText: String {
        if self < 1_000_000 {
            return String(localized: "\(self / 1000) kbps")
        }
        let megabits = (Double(self) / 1_000_000).formatted(.number.precision(.fractionLength(0 ... 1)))
        return String(localized: "\(megabits) Mbps")
    }
}
