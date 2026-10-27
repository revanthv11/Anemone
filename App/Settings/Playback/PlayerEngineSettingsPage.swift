import AnemoneCore
import AnemonePlayback
import AnemoneUI
import SwiftUI

/// Settings › Playback › Player: which engine plays video, Wholphin's "Playback Backend", with
/// its MPV options and the style of the subtitles MPV draws. A change applies to the next video
/// played.
struct PlayerEngineSettingsPage: View {
    @AppStorage(Preferences.playerBackend) private var backend
    @AppStorage(Preferences.mpvHardwareDecoding) private var hardwareDecoding
    @AppStorage(Preferences.mpvGpuNext) private var gpuNext
    @AppStorage(Preferences.subtitleStyleSeparateHDR) private var separateHDR

    var body: some View {
        List {
            Section {
                Picker("Playback backend", selection: $backend) {
                    ForEach(PlayerBackend.allCases, id: \.self) { backend in
                        Text(backend.title).tag(backend)
                    }
                }
                .pickerStyle(.navigationLink)
                .accessibilityIdentifier("settings.playerBackend")
            } footer: {
                Text(backend.explanation)
            }
            if backend != .avPlayer {
                Section("MPV") {
                    Toggle("Use hardware decoding", isOn: $hardwareDecoding)
                        .accessibilityIdentifier("settings.mpvHardwareDecoding")
                    Toggle("Use gpu-next", isOn: $gpuNext)
                        .accessibilityIdentifier("settings.mpvGpuNext")
                }
                Section {
                    NavigationLink("Subtitle style") {
                        SubtitleStylePage(preference: Preferences.subtitleStyle, title: "Subtitle Style")
                    }
                    .accessibilityIdentifier("settings.subtitleStyle")
                    Toggle("Use a different style for HDR", isOn: $separateHDR)
                        .accessibilityIdentifier("settings.subtitleStyleSeparateHDR")
                    if separateHDR {
                        NavigationLink("HDR subtitle style") {
                            SubtitleStylePage(preference: Preferences.hdrSubtitleStyle, title: "HDR Subtitle Style")
                        }
                        .accessibilityIdentifier("settings.hdrSubtitleStyle")
                    }
                } header: {
                    Text("Subtitles")
                } footer: {
                    Text("For the subtitles MPV draws. ASS subtitles keep their own styling.")
                }
            }
        }
        .navigationTitle("Player")
    }
}

extension PlayerBackend {
    /// Wholphin's names, with AVPlayer in place of ExoPlayer.
    var title: String {
        switch self {
        case .avPlayer: "AVPlayer"
        case .mpv: "MPV"
        case .preferMPV: "Prefer MPV"
        }
    }

    var explanation: String {
        switch self {
        case .avPlayer:
            "Apple's player: Dolby Vision, Dolby Atmos and frame-rate matching. The server converts what it can't "
                + "play, such as DTS audio or styled subtitles."
        case .mpv:
            "MPV plays nearly anything as it is, including MKV, DTS, TrueHD and styled ASS and PGS subtitles, "
                + "with Anemone's controls. No Dolby Vision."
        case .preferMPV:
            "MPV, except HDR and Dolby Vision video, which plays in AVPlayer."
        }
    }
}
