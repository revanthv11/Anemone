import AnemoneCore
import AnemonePlayback
import AnemoneUI
import SwiftUI

/// Settings › Playback › Cinema Mode: Wholphin's switch for the server's intros before a movie.
struct CinemaModeSettingsPage: View {
    @AppStorage(Preferences.cinemaMode) private var cinemaMode

    var body: some View {
        List {
            Section {
                Toggle("Cinema mode", isOn: $cinemaMode)
                    .accessibilityIdentifier("settings.cinemaMode")
            } footer: {
                Text("Plays the intros the server has, such as trailers or pre-rolls, before what you play from "
                    + "the beginning. The server's admin sets them up, for example with the Local Intros plugin.")
            }
        }
        .navigationTitle("Cinema Mode")
    }
}
