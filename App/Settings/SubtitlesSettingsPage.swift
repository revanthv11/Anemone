import AnemoneCore
import SwiftUI

/// Settings › Subtitles: the preferred subtitle language and when subtitles show, and later
/// (Phase 4) their style. The same settings as in Settings › Playback › Audio and Subtitles.
struct SubtitlesSettingsPage: View {
    @Environment(BrowseModel.self) private var browse
    @State private var model = TrackSettingsModel()

    var body: some View {
        List {
            SubtitleSettingRows(model: model)
        }
        .navigationTitle("Subtitles")
        .task {
            await model.load(from: browse.session)
        }
    }
}

/// The subtitle language and mode rows.
struct SubtitleSettingRows: View {
    let model: TrackSettingsModel

    @AppStorage(Preferences.preferredSubtitleLanguage) private var language: LanguageSetting
    @AppStorage(Preferences.subtitleMode) private var mode: SubtitleModeSetting

    var body: some View {
        LanguageSettingRow(
            title: String(localized: "Subtitle language"),
            id: "subtitleLanguage",
            setting: $language,
            profileLanguage: model.profile.subtitleLanguage,
            model: model,
        )
        NavigationLink {
            ChoicePage(title: String(localized: "Show Subtitles"), selection: $mode, choices: modes)
        } label: {
            LabeledContent(
                "Show subtitles",
                value: mode == .serverProfile ? String(localized: "Jellyfin profile (\(profileMode.title))") : mode
                    .title,
            )
        }
        .accessibilityIdentifier("settings.subtitleMode")
    }

    /// What the Jellyfin profile says, which Jellyfin itself defaults to Default.
    private var profileMode: SubtitleModeSetting {
        model.profile.subtitleMode.flatMap { SubtitleModeSetting(rawValue: $0.rawValue) } ?? .default
    }

    private var modes: [ChoicePage<SubtitleModeSetting>.Choice] {
        SubtitleModeSetting.allCases.map { mode in
            .init(mode, mode.title, detail: mode == .serverProfile ? profileMode.title : mode.explanation)
        }
    }
}

private extension SubtitleModeSetting {
    var title: String {
        switch self {
        case .serverProfile: String(localized: "From your Jellyfin profile")
        case .default: String(localized: "Default")
        case .smart: String(localized: "Smart")
        case .onlyForced: String(localized: "Only forced")
        case .always: String(localized: "Always")
        case .none: String(localized: "Never")
        }
    }

    /// Jellyfin's descriptions of its modes, shortened.
    var explanation: String? {
        switch self {
        case .serverProfile: nil
        case .default: String(localized: "Subtitles marked default or forced in the file")
        case .smart: String(localized: "Subtitles when the audio is in another language, otherwise forced ones")
        case .onlyForced: String(localized: "Only forced subtitles, such as for signs")
        case .always: String(localized: "Subtitles in your language whenever there are some")
        case .none: String(localized: "No subtitles unless you pick some")
        }
    }
}
