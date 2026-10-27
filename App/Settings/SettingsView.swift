import AnemoneCore
import SwiftUI

/// Settings: the account, then a page for each part of the app. Each page lives in its own
/// file, so the parts of the app that add settings don't share one.
struct SettingsView: View {
    let server: SavedServer
    let user: SavedUser

    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Signed in as \(user.name)")
                            .accessibilityIdentifier("settings.signedInAs")
                        Text("\(server.name) · Jellyfin \(server.version)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Button("Switch user") {
                        model.switchUser()
                    }
                    NavigationLink("Profile lock") {
                        ProfileLockView(user: user)
                    }
                    Button("Sign out") {
                        model.signOut()
                    }
                    .accessibilityIdentifier("settings.signOut")
                }
                Section {
                    page("Sidebar", systemImage: "sidebar.left", id: "sidebar") {
                        SidebarSettingsView()
                    }
                    page("Home", systemImage: "house", id: "home") {
                        HomeSettingsPage()
                    }
                    page("Playback", systemImage: "play.rectangle", id: "playback") {
                        PlaybackSettingsPage()
                    }
                    page("Subtitles", systemImage: "captions.bubble", id: "subtitles") {
                        SubtitlesSettingsPage()
                    }
                    page("Appearance", systemImage: "paintpalette", id: "appearance") {
                        AppearanceSettingsPage()
                    }
                    page("Screensaver", systemImage: "sparkles.tv", id: "screensaver") {
                        ScreensaverSettingsPage()
                    }
                    page("About", systemImage: "info.circle", id: "about") {
                        AboutSettingsPage()
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func page(
        _ title: String,
        systemImage: String,
        id: String,
        @ViewBuilder destination: () -> some View,
    ) -> some View {
        NavigationLink(destination: destination) {
            Label(title, systemImage: systemImage)
        }
        .accessibilityIdentifier("settings.\(id)")
    }
}

/// A settings page whose settings come later.
struct SettingsPlaceholder: View {
    let title: String
    let message: String

    var body: some View {
        Text(message)
            .foregroundStyle(.secondary)
            // Gives focus somewhere to rest.
            .focusable()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(80)
            .navigationTitle(title)
    }
}
