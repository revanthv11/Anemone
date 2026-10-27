import AnemoneCore
import AnemonePlayback
import AnemoneUI
import AVFoundation
import AVKit
import SwiftUI

/// The full-screen player: the system player with its transport bar and info panel, or Anemone's
/// own overlay when Settings asks for it. What features add shows through either.
struct PlayerScreen: View {
    let playback: PlaybackController

    @Environment(BrowseModel.self) private var browse
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Preferences.playerControls) private var controls

    var body: some View {
        Group {
            if case let .failed(error) = playback.state {
                PlaybackFailure(message: browse.playbackProblem(with: error)) {
                    dismiss()
                }
            } else {
                video
                    .overlay {
                        if case .loading = playback.state {
                            ProgressView()
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if let card = playback.accessories.card {
                            PlayerCardView(card: card)
                                .padding(80)
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

    @ViewBuilder
    private var video: some View {
        switch playback.engine.videoOutput {
        case let .avPlayer(player) where controls == .system:
            let accessories = playback.accessories
            SystemPlayer(
                player: player,
                accessories: accessories,
                shown: SystemPlayer.Shown(actions: accessories.actions, menus: accessories.menus),
            )
        default:
            // Engines that draw their own layer, such as MPV, always need Anemone's overlay.
            AnemonePlayer(playback: playback)
        }
    }
}

/// AVKit's player, which brings the Siri Remote's scrubbing, the info panel with audio and
/// subtitle choices, and Now Playing. Features' actions become its contextual actions (like
/// "Skip Intro"), and their menus sit above its transport bar.
private struct SystemPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    let accessories: PlayerAccessories
    /// What the accessories looked like, read in the screen's body so changes update the player.
    let shown: Shown

    func makeUIViewController(context _: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
        // Only when they change, so the player doesn't bring its contextual actions back up.
        guard context.coordinator.shown != shown else { return }
        context.coordinator.shown = shown
        controller.contextualActions = accessories.actions.map(action)
        controller.transportBarCustomMenuItems = accessories.menus.map(menu)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var shown: Shown?
    }

    /// Handlers look the action up when they run, so they call what the feature shows now.
    private func action(_ action: PlayerAction) -> UIAction {
        let id = action.id
        let accessories = accessories
        return UIAction(title: action.title, image: action.systemImage.flatMap(UIImage.init(systemName:))) { _ in
            accessories.actions.first { $0.id == id }?.perform()
        }
    }

    /// One level only: AVKit doesn't support menus inside these.
    private func menu(_ menu: PlayerMenu) -> UIMenu {
        let menuID = menu.id
        let accessories = accessories
        return UIMenu(
            title: menu.title,
            image: menu.systemImage.flatMap(UIImage.init(systemName:)),
            children: menu.options.map { option in
                let optionID = option.id
                return UIAction(title: option.title, state: option.isSelected ? .on : .off) { _ in
                    accessories.menus.first { $0.id == menuID }?.options.first { $0.id == optionID }?.select()
                }
            },
        )
    }

    /// The parts of the accessories the system player shows.
    struct Shown: Equatable {
        private let actions: [[String?]]
        private let menus: [[String?]]

        init(actions: [PlayerAction], menus: [PlayerMenu]) {
            self.actions = actions.map { [$0.id, $0.title, $0.systemImage] }
            self.menus = menus.map { menu in
                [menu.id, menu.title, menu.systemImage]
                    + menu.options.flatMap { [$0.id, $0.title, $0.isSelected ? "on" : "off"] }
            }
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
    /// Shows a player for `request` full screen while it's set. When the player closes, ends the
    /// play session and then runs `closed`, so the page can show the new resume position.
    func player(_ request: Binding<PlaybackRequest?>, closed: @escaping () async -> Void) -> some View {
        modifier(PlayerPresenter(request: request, closed: closed))
    }
}

private struct PlayerPresenter: ViewModifier {
    @Binding var request: PlaybackRequest?
    let closed: () async -> Void

    @Environment(BrowseModel.self) private var browse
    /// Built from `request`, which is cleared once it has a player.
    @State private var playback: PlaybackController?
    /// The player on screen. The cover clears `playback` before `onDismiss` runs, so this keeps
    /// it for ending the session.
    @State private var shown: PlaybackController?

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $playback, onDismiss: close) { playback in
                PlayerScreen(playback: playback)
                    .onAppear { shown = playback }
            }
            .onChange(of: request?.id) {
                guard let request else { return }
                self.request = nil
                playback = browse.player(for: request)
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
