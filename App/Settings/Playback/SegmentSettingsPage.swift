import AnemoneCore
import AnemoneJellyfin
import AnemonePlayback
import AnemoneUI
import SwiftUI

/// Settings › Playback › Skip Segments: what the player does at intros, credits, commercials,
/// previews and recaps. Wholphin's skip settings, in its order.
struct SegmentSettingsPage: View {
    private static let kinds: [MediaSegment.Kind] = [.intro, .outro, .commercial, .preview, .recap]

    var body: some View {
        List {
            Section {
                ForEach(Self.kinds, id: \.self) { kind in
                    BehaviorRow(kind: kind)
                }
            } footer: {
                Text("Segments come from the server, when a plugin there finds them.")
            }
        }
        .navigationTitle("Skip Segments")
    }
}

/// The setting for one kind of segment, with its choices on a page of their own, as Wholphin
/// lists them in a dialog. A `Picker` here would be segmented, which hides its label on tvOS.
private struct BehaviorRow: View {
    let kind: MediaSegment.Kind
    @AppStorage private var behavior: SkipSegmentBehavior

    init(kind: MediaSegment.Kind) {
        self.kind = kind
        _behavior = AppStorage(Preferences.skipBehavior(for: kind))
    }

    var body: some View {
        NavigationLink {
            BehaviorChoices(title: kind.settingTitle, behavior: $behavior)
        } label: {
            LabeledContent(kind.settingTitle, value: behavior.title)
        }
        .accessibilityIdentifier("settings.skip.\(kind.rawValue)")
    }
}

/// Choosing goes back to the list.
private struct BehaviorChoices: View {
    let title: String
    @Binding var behavior: SkipSegmentBehavior

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(SkipSegmentBehavior.allCases, id: \.self) { choice in
            Button {
                behavior = choice
                dismiss()
            } label: {
                HStack {
                    Text(choice.title)
                    Spacer()
                    if choice == behavior {
                        Image(systemName: "checkmark")
                            .accessibilityHidden(true)
                    }
                }
            }
            // The check, for VoiceOver.
            .accessibilityAddTraits(choice == behavior ? .isSelected : [])
            .accessibilityIdentifier("settings.skip.choice.\(choice.rawValue)")
        }
        .navigationTitle(title)
    }
}

private extension MediaSegment.Kind {
    var settingTitle: String {
        switch self {
        case .intro: String(localized: "Intros")
        case .outro: String(localized: "Outros")
        case .commercial: String(localized: "Commercials")
        case .preview: String(localized: "Previews")
        case .recap: String(localized: "Recaps")
        }
    }
}

private extension SkipSegmentBehavior {
    /// Wholphin's names for the choices.
    var title: String {
        switch self {
        case .ignore: String(localized: "Ignore")
        case .ask: String(localized: "Ask to skip")
        case .autoSkip: String(localized: "Skip automatically")
        }
    }
}
