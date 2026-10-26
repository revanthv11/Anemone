import AnemonePlayback
import AVFoundation
import AVKit
import SwiftUI

/// The full-screen player: the system player with its transport bar and info panel, until
/// Anemone's own overlay comes later in Phase 3.
struct PlayerScreen: View {
    let playback: PlaybackController

    @Environment(BrowseModel.self) private var browse
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if case let .failed(error) = playback.state {
                PlaybackFailure(message: browse.playbackProblem(with: error)) {
                    dismiss()
                }
            } else {
                SystemPlayer(player: playback.player)
                    .overlay {
                        if case .loading = playback.state {
                            ProgressView()
                        }
                    }
            }
        }
        .background(.black)
        .ignoresSafeArea()
        .task {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            await playback.start()
        }
        // Like Wholphin with nothing up next: back to the page at the end.
        .onChange(of: playback.hasEnded) { _, hasEnded in
            if hasEnded {
                dismiss()
            }
        }
    }
}

/// AVKit's player, which brings the Siri Remote's scrubbing, the info panel with audio and
/// subtitle choices, and Now Playing.
private struct SystemPlayer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context _: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context _: Context) {
        if controller.player !== player {
            controller.player = player
        }
    }
}

/// Why playback stopped, with a way back to the page.
private struct PlaybackFailure: View {
    let message: String
    let close: () -> Void

    var body: some View {
        VStack(spacing: 40) {
            Text("Can't play this")
                .font(.title2.bold())
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 1000)
            Button("OK", action: close)
                .accessibilityIdentifier("player.close")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("player.failure")
    }
}

extension View {
    /// Shows `playback` full screen while it's set. When the player closes, ends the play session
    /// and then runs `closed`, so the page can show the new resume position.
    func player(_ playback: Binding<PlaybackController?>, closed: @escaping () async -> Void) -> some View {
        modifier(PlayerPresenter(playback: playback, closed: closed))
    }
}

private struct PlayerPresenter: ViewModifier {
    @Binding var playback: PlaybackController?
    let closed: () async -> Void
    /// The player on screen. The cover clears `playback` before `onDismiss` runs, so this keeps
    /// it for ending the session.
    @State private var shown: PlaybackController?

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $playback, onDismiss: close) { playback in
                PlayerScreen(playback: playback)
                    .onAppear { shown = playback }
            }
    }

    private func close() {
        guard let ended = shown else { return }
        shown = nil
        Task {
            await ended.stop()
            await closed()
        }
    }
}
