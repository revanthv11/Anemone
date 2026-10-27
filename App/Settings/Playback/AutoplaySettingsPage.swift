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
                ChoiceRow(
                    title: String(localized: "Show Up Next"),
                    selection: $timing,
                    choices: UpNextTiming.allCases,
                    name: \.title,
                )
                .accessibilityIdentifier("autoplay.timing")
            } footer: {
                Text("During the credits needs the server to know where they start; otherwise it shows at the end.")
            }
            Section {
                Toggle("Autoplay next", isOn: $autoPlayNext)
                    .accessibilityIdentifier("autoplay.enabled")
                ChoiceRow(
                    title: String(localized: "Countdown"),
                    selection: $countdown,
                    choices: Self.countdowns,
                ) { seconds in
                    seconds == 0 ? String(localized: "Immediate") : String(localized: "\(seconds) seconds")
                }
                .disabled(!autoPlayNext)
                .accessibilityIdentifier("autoplay.countdown")
            }
            Section {
                ChoiceRow(
                    title: String(localized: "Ask \"Still watching?\""),
                    selection: $passOutCount,
                    choices: Self.passOutCounts,
                    name: Self.passOutText,
                )
                .disabled(!autoPlayNext)
                .accessibilityIdentifier("autoplay.stillWatching")
            } footer: {
                Text("""
                Asks once this many videos in a row have played on their own, with no press on the remote, \
                and stops playback when nobody answers.
                """)
            }
        }
        .navigationTitle("Autoplay")
    }

    /// Wholphin's slider: 0 to 60 seconds in steps of 5.
    private static let countdowns = Array(stride(from: 0, through: 60, by: 5))
    private static let passOutCounts = Array(0 ... 5)

    private static func passOutText(_ count: Int) -> String {
        // One key with plural forms in the String Catalog, not "1 autoplay" spelled out.
        count == 0 ? String(localized: "Never") : String(localized: "After \(count) autoplays")
    }
}

/// A setting with its current choice, opening a page of the choices, like the rows in Skip
/// Segments. A `Picker` in a list is segmented on tvOS, which hides its title.
private struct ChoiceRow<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let choices: [Value]
    let name: (Value) -> String

    var body: some View {
        NavigationLink {
            Choices(title: title, selection: $selection, choices: choices, name: name)
        } label: {
            LabeledContent(title, value: name(selection))
        }
    }
}

/// Choosing goes back to the list.
private struct Choices<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let choices: [Value]
    let name: (Value) -> String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(choices, id: \.self) { choice in
            Button {
                selection = choice
                dismiss()
            } label: {
                HStack {
                    Text(name(choice))
                    Spacer()
                    if choice == selection {
                        Image(systemName: "checkmark")
                            .accessibilityHidden(true)
                    }
                }
            }
            // The check, for VoiceOver.
            .accessibilityAddTraits(choice == selection ? .isSelected : [])
        }
        .navigationTitle(title)
    }
}

private extension UpNextTiming {
    var title: String {
        switch self {
        case .endOfPlayback: String(localized: "At the end")
        case .duringCredits: String(localized: "During the credits")
        }
    }
}
