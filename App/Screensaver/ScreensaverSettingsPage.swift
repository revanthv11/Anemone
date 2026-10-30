import AnemoneCore
import AnemoneJellyfin
import AnemoneUI
import SwiftUI

/// Settings › Screensaver: Wholphin's in-app screensaver settings (`ScreensaverPreference`),
/// with its "Dim screen" group. The screensaver shows the backdrops of random movies and shows,
/// and photos when they're included, after the remote has been left alone for a while; Apple
/// TV's own screensaver still takes over later.
struct ScreensaverSettingsPage: View {
    @AppStorage(Preferences.screensaverEnabled) private var isEnabled
    @AppStorage(Preferences.screensaverStartDelay) private var startDelay
    @AppStorage(Preferences.screensaverDuration) private var duration
    @AppStorage(Preferences.screensaverShowClock) private var showsClock
    @AppStorage(Preferences.screensaverAnimate) private var animates
    @AppStorage(Preferences.screensaverMaxAge) private var maxAge
    @AppStorage(Preferences.screensaverItemTypes) private var itemTypes
    @AppStorage(Preferences.screensaverDimEnabled) private var dims
    @AppStorage(Preferences.screensaverDimPercent) private var dimPercent

    @Environment(Screensaver.self) private var screensaver: Screensaver?

    var body: some View {
        List {
            Section {
                Toggle("Use in-app screensaver", isOn: $isEnabled)
                    .accessibilityIdentifier("screensaver.enabled")
                ScreensaverChoiceRow(
                    title: String(localized: "Start after"),
                    selection: $startDelay,
                    choices: ScreensaverChoices.startDelays,
                    name: Self.durationText,
                )
                // The delay is the dimming's too.
                .disabled(!isEnabled && !dims)
                .accessibilityIdentifier("screensaver.startDelay")
            } footer: {
                Text("""
                Shows the backdrops of random movies and shows once the remote has been left alone, \
                but never while a video plays.
                """)
            }
            Section {
                ScreensaverChoiceRow(
                    title: String(localized: "Each picture for"),
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
                    title: String(localized: "Max age rating"),
                    selection: $maxAge,
                    choices: ScreensaverChoices.maxAges,
                    name: Self.ageText,
                )
                .accessibilityIdentifier("screensaver.maxAge")
                NavigationLink {
                    ScreensaverTypesList(types: $itemTypes)
                } label: {
                    LabeledContent(String(localized: "Include types"), value: Self.typesText(itemTypes))
                }
                .accessibilityIdentifier("screensaver.itemTypes")
            }
            Section {
                Button("Start screensaver") {
                    screensaver?.start()
                }
                .accessibilityIdentifier("screensaver.start")
            }
            Section {
                Toggle("Dim screen after delay", isOn: $dims)
                    .accessibilityIdentifier("screensaver.dim")
                ScreensaverChoiceRow(
                    title: String(localized: "Dim percentage"),
                    selection: $dimPercent,
                    choices: ScreensaverChoices.dimPercents,
                    name: Self.percentText,
                )
                .disabled(!dims)
                .accessibilityIdentifier("screensaver.dimPercent")
            } header: {
                Text("Dim screen")
            } footer: {
                Text("""
                Darkens the screen once the remote has been left alone for the time above, with the \
                screensaver or without it.
                """)
            }
        }
        .navigationTitle("Screensaver")
    }

    /// The types included, in Wholphin's order, as a list.
    private static func typesText(_ types: ScreensaverItemTypes) -> String {
        let names = ScreensaverItemTypes.Kind.allCases.filter(types.contains).map(\.title)
        return names.isEmpty ? String(localized: "None") : names.formatted(.list(type: .and, width: .short))
    }

    private static func percentText(_ percent: Int) -> String {
        (Double(percent) / 100).formatted(.percent.precision(.fractionLength(0)))
    }

    private static func durationText(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }

    /// As Wholphin words them.
    private static func ageText(_ age: Int) -> String {
        switch age {
        case -1: String(localized: "No limit")
        case 0: String(localized: "For all ages")
        default: String(localized: "Up to age \(age)")
        }
    }
}

/// Wholphin's "Include types": a switch for each type of item the screensaver can show.
private struct ScreensaverTypesList: View {
    @Binding var types: ScreensaverItemTypes

    var body: some View {
        List(ScreensaverItemTypes.Kind.allCases, id: \.self) { kind in
            Toggle(kind.title, isOn: Binding(
                get: { types.contains(kind) },
                set: { types.set(kind, included: $0) },
            ))
            .accessibilityIdentifier("screensaver.itemTypes.\(kind.rawValue)")
        }
        .navigationTitle("Include types")
    }
}

private extension ScreensaverItemTypes.Kind {
    /// Wholphin's names for them (`screensaver_item_types`).
    var title: String {
        switch self {
        case .movie: String(localized: "Movies")
        case .series: String(localized: "TV Shows")
        case .photo: String(localized: "Photos")
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
                            .accessibilityHidden(true)
                    }
                }
            }
            // VoiceOver hears the check as the row being selected.
            .accessibilityAddTraits(choice == selection ? .isSelected : [])
        }
        .navigationTitle(title)
    }
}
