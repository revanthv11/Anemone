import AnemonePlayback
import AVFoundation
import Combine
import SwiftUI

/// A clip in a photo album, playing in the slideshow as Wholphin plays it: the file as it is,
/// with no play session or progress reports. In the viewer it plays over and over; in a running
/// slideshow it plays once, and the slideshow moves on after it, or when it fails.
@MainActor
@Observable
final class ClipPlayer {
    /// What the slideshow hears.
    enum Event {
        /// Ready and playing, this long when known.
        case playing(length: Duration?)
        case ended
        case failed
    }

    let player: AVPlayer
    /// Plays again from the start at the end, rather than telling the slideshow it ended.
    var loops = true
    private(set) var isPaused = false
    private(set) var hasFailed = false
    @ObservationIgnored private let tell: @MainActor (Event) -> Void
    @ObservationIgnored private var watching: [Task<Void, Never>] = []

    init(url: URL, tell: @escaping @MainActor (Event) -> Void) {
        player = AVPlayer(url: url)
        self.tell = tell
        guard let item = player.currentItem else { return }
        watching = [
            Task { [weak self] in
                let statuses = item.publisher(for: \.status).buffer(size: 8, prefetch: .keepFull, whenFull: .dropOldest)
                for await status in statuses.values {
                    switch status {
                    case .readyToPlay:
                        let length = item.duration
                        self?.tell(.playing(length: length.isNumeric ? .seconds(length.seconds) : nil))
                        return
                    case .failed:
                        self?.failed()
                        return
                    default:
                        continue
                    }
                }
            },
            Task { [weak self] in
                let failures = NotificationCenter.default.notifications(
                    named: AVPlayerItem.failedToPlayToEndTimeNotification,
                    object: item,
                )
                for await _ in failures {
                    self?.failed()
                    return
                }
            },
            Task { [weak self] in
                let ends = NotificationCenter.default.notifications(
                    named: AVPlayerItem.didPlayToEndTimeNotification,
                    object: item,
                )
                for await _ in ends {
                    self?.reachedEnd()
                }
            },
        ]
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
        watching.forEach { $0.cancel() }
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    private func reachedEnd() {
        if loops {
            player.seek(to: .zero)
            player.play()
        } else {
            tell(.ended)
        }
    }

    private func failed() {
        guard !hasFailed else { return }
        hasFailed = true
        tell(.failed)
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
