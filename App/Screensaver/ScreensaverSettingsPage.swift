import AnemoneCore
import AnemoneUI
import SwiftUI

/// Settings › Screensaver: Wholphin's in-app screensaver settings (`ScreensaverPreference`).
/// The screensaver shows the backdrops of random movies and shows after the remote has been
/// left alone for a while; Apple TV's own screensaver still takes over later.
struct ScreensaverSettingsPage: View {
    @AppStorage(Preferences.screensaverEnabled) private var isEnabled
    @AppStorage(Preferences.screensaverStartDelay) private var startDelay
    @AppStorage(Preferences.screensaverDuration) private var duration
    @AppStorage(Preferences.screensaverShowClock) private var showsClock
    @AppStorage(Preferences.screensaverAnimate) private var animates
    @AppStorage(Preferences.screensaverMaxAge) private var maxAge

    @Environment(Screensaver.self) private var screensaver: Screensaver?

    var body: some View {
        List {
            Section {
                Toggle("Use in-app screensaver", isOn: $isEnabled)
                    .accessibilityIdentifier("screensaver.enabled")
                ScreensaverChoiceRow(
                    title: "Start after",
                    selection: $startDelay,
                    choices: ScreensaverChoices.startDelays,
                    name: Self.durationText,
                )
                .disabled(!isEnabled)
                .accessibilityIdentifier("screensaver.startDelay")
            } footer: {
                Text("Shows the backdrops of random movies and shows once the remote has been left alone, "
                    + "but never while a video plays.")
            }
            Section {
                ScreensaverChoiceRow(
                    title: "Each picture for",
                    selection: $duration,
                    choices: ScreensaverChoices.durations,
                    name: Self.durationText,
                )
                .accessibilityIdentifier("screensaver.duration")
                Toggle("Show clock", isOn: $showsClock)
                    .accessibilityIdentifier("screensaver.clock")
                Toggle("Animate", isOn: $animates)
                    .accessibilityIdentifier("screensaver.animate")
                ScreensaverChoiceRow(
                    title: "Max age rating",
                    selection: $maxAge,
                    choices: ScreensaverChoices.maxAges,
                    name: Self.ageText,
                )
                .accessibilityIdentifier("screensaver.maxAge")
            }
            Section {
                Button("Start screensaver") {
                    screensaver?.start()
                }
                .accessibilityIdentifier("screensaver.start")
            }
        }
        .navigationTitle("Screensaver")
    }

    private static func durationText(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }

    /// As Wholphin words them.
    private static func ageText(_ age: Int) -> String {
        switch age {
        case -1: "No limit"
        case 0: "For all ages"
        default: "Up to age \(age)"
        }
    }
}

/// A setting with its current choice, opening a page of the choices, like Settings › Playback's
/// rows. A `Picker` in a list is segmented on tvOS, which hides its title.
private struct ScreensaverChoiceRow<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let choices: [Value]
    let name: (Value) -> String

    var body: some View {
        NavigationLink {
            ScreensaverChoiceList(title: title, selection: $selection, choices: choices, name: name)
        } label: {
            LabeledContent(title, value: name(selection))
        }
    }
}

/// Choosing goes back to the list.
private struct ScreensaverChoiceList<Value: Hashable>: View {
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
                    }
                }
            }
        }
        .navigationTitle(title)
    }
}
