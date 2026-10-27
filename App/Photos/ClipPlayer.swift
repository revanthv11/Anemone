import AnemonePlayback
import AVFoundation
import SwiftUI

/// A clip in a photo album, playing in the slideshow as Wholphin plays it: the file as it is,
/// with no play session or progress reports. In the viewer it plays over and over; in a running
/// slideshow it plays once, and the slideshow moves on after it.
@MainActor
@Observable
final class ClipPlayer {
    let player: AVPlayer
    /// Plays again from the start at the end, rather than telling the slideshow it ended.
    var loops = true
    private(set) var isPaused = false
    @ObservationIgnored private let ended: @MainActor () -> Void
    @ObservationIgnored private var watching: Task<Void, Never>?

    init(url: URL, ended: @escaping @MainActor () -> Void) {
        player = AVPlayer(url: url)
        self.ended = ended
        let item = player.currentItem
        watching = Task { [weak self] in
            let ends = NotificationCenter.default.notifications(
                named: AVPlayerItem.didPlayToEndTimeNotification,
                object: item,
            )
            for await _ in ends {
                self?.reachedEnd()
            }
        }
    }

    func play() {
        isPaused = false
        player.play()
    }

    func togglePause() {
        if isPaused {
            play()
        } else {
            isPaused = true
            player.pause()
        }
    }

    func stop() {
        watching?.cancel()
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    private func reachedEnd() {
        if loops {
            player.seek(to: .zero)
            player.play()
        } else {
            ended()
        }
    }
}

/// The clip's picture, fitted to the screen, in the view Anemone's player overlay shows video in.
struct ClipView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context _: Context) -> PlayerVideoView {
        let view = PlayerVideoView()
        view.output = .avPlayer(player)
        return view
    }

    func updateUIView(_ view: PlayerVideoView, context _: Context) {
        if case let .avPlayer(shown) = view.output, shown === player {
            return
        }
        view.output = .avPlayer(player)
    }
}
