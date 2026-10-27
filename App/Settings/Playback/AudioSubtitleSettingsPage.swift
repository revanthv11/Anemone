import AnemoneCore
import AnemoneJellyfin
import SwiftUI

/// Settings › Playback › Audio and Subtitles: the languages tracks are chosen in, when subtitles
/// show, and forgetting what was picked in the player. Wholphin's profile-specific settings,
/// which fall back to the user's Jellyfin profile.
struct AudioSubtitleSettingsPage: View {
    @Environment(BrowseModel.self) private var browse
    @AppStorage(Preferences.preferredAudioLanguage) private var audioLanguage: LanguageSetting
    @State private var model = TrackSettingsModel()
    @State private var forgotten = false

    var body: some View {
        List {
            Section {
                LanguageSettingRow(
                    title: String(localized: "Audio language"),
                    id: "audioLanguage",
                    setting: $audioLanguage,
                    profileLanguage: model.profile.audioLanguage,
                    model: model,
                )
                SubtitleSettingRows(model: model)
            } footer: {
                Text("""
                Tracks you pick in the player win over these, for that item and, for an episode, the rest of \
                its season and series.
                """)
            }
            Section {
                Button("Forget picked tracks") {
                    TrackChoiceStore(userID: browse.session.userID).removeAll()
                    forgotten = true
                }
                .disabled(forgotten)
                .accessibilityIdentifier("settings.forgetTracks")
            }
        }
        .navigationTitle("Audio and Subtitles")
        .task {
            await model.load(from: browse.session)
        }
    }
}

/// The server's languages and the Jellyfin profile's track settings, which the rows show.
@MainActor
@Observable
final class TrackSettingsModel {
    private(set) var languages: [ServerLanguage] = []
    private(set) var profile = ProfileTrackSettings()

    func load(from session: JellyfinSession) async {
        async let languages = try? session.languages()
        async let profile = try? session.profileTrackSettings()
        self.languages = await languages ?? []
        self.profile = await profile ?? ProfileTrackSettings()
    }

    /// The server's name for a language code, else the system's.
    func name(of code: String?) -> String? {
        guard let code, !LanguageCode.isUnknown(code) else { return nil }
        return languages.first { LanguageCode.same($0.code, code) }?.name
            ?? Locale.current.localizedString(forLanguageCode: code)
            ?? code
    }
}

/// A preferred-language setting, picked on a page of the server's languages.
struct LanguageSettingRow: View {
    let title: String
    let id: String
    @Binding var setting: LanguageSetting
    /// What the Jellyfin profile says, which `.serverProfile` stands for.
    let profileLanguage: String?
    let model: TrackSettingsModel

    var body: some View {
        NavigationLink {
            ChoicePage(title: title, selection: $setting, choices: choices)
        } label: {
            LabeledContent(title, value: summary)
        }
        .accessibilityIdentifier("settings.\(id)")
    }

    private var summary: String {
        switch setting {
        case .serverProfile:
            String(localized: "Jellyfin profile (\(model.name(of: profileLanguage) ?? String(localized: "any")))")
        case .anyLanguage: String(localized: "Any")
        case let .language(code): model.name(of: code) ?? code
        }
    }

    private var choices: [ChoicePage<LanguageSetting>.Choice] {
        var choices: [ChoicePage<LanguageSetting>.Choice] = [
            .init(
                .serverProfile,
                String(localized: "From your Jellyfin profile"),
                detail: model.name(of: profileLanguage) ?? String(localized: "Any language"),
            ),
            .init(.anyLanguage, String(localized: "Any language")),
        ]
        // Keeps a language the server's list doesn't have, so it still shows as picked.
        if case let .language(code) = setting, !model.languages.contains(where: { $0.code == code }) {
            choices.append(.init(setting, model.name(of: code) ?? code))
        }
        return choices + model.languages.map { .init(.language($0.code), $0.name) }
    }
}

/// A page of choices for one setting; picking one goes back.
struct ChoicePage<Value: Hashable>: View {
    struct Choice: Identifiable {
        let value: Value
        let title: String
        var detail: String?

        var id: Value {
            value
        }

        init(_ value: Value, _ title: String, detail: String? = nil) {
            self.value = value
            self.title = title
            self.detail = detail
        }
    }

    let title: String
    @Binding var selection: Value
    let choices: [Choice]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(choices) { choice in
            Button {
                selection = choice.value
                dismiss()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(choice.title)
                        if let detail = choice.detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if choice.value == selection {
                        Image(systemName: "checkmark")
                            .accessibilityHidden(true)
                    }
                }
            }
            // The check, for VoiceOver.
            .accessibilityAddTraits(choice.value == selection ? .isSelected : [])
        }
        .navigationTitle(title)
    }
}
