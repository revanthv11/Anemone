import Foundation
#if canImport(AVFoundation)
    import AVFoundation
#endif

/// What plays a theme song: AVPlayer in the app, a fake in tests.
@MainActor
protocol ThemeMusicOutput: AnyObject {
    /// Plays the song once, from the start.
    func play(_ url: URL, volume: Float)
    func stop()
}

/// AVPlayer on its own, outside `PlayerEngine`, Now Playing and the remote commands: a theme
/// is background sound for a page, not something the user is playing.
@MainActor
final class SystemThemeMusicOutput: ThemeMusicOutput {
    #if canImport(AVFoundation)
        private var player: AVPlayer?
        #if os(tvOS) || os(iOS)
            /// The audio session's category before the song, to put back after it.
            private var previousCategory: (AVAudioSession.Category, AVAudioSession.Mode)?
        #endif
    #endif

    func play(_ url: URL, volume: Float) {
        #if canImport(AVFoundation)
            stop()
            #if os(tvOS) || os(iOS)
                // Ambient sound mixes with other audio, so tvOS doesn't make Anemone the Now
                // Playing app or send it the remote's play and pause for a theme song.
                let session = AVAudioSession.sharedInstance()
                if session.category != .ambient {
                    previousCategory = (session.category, session.mode)
                    try? session.setCategory(.ambient)
                }
            #endif
            let player = AVPlayer(url: url)
            player.volume = volume
            player.play()
            self.player = player
        #endif
    }

    func stop() {
        #if canImport(AVFoundation)
            player?.pause()
            player = nil
            #if os(tvOS) || os(iOS)
                // Unless something else changed it meanwhile, as the video player does.
                let session = AVAudioSession.sharedInstance()
                if let previous = previousCategory, session.category == .ambient {
                    try? session.setCategory(previous.0, mode: previous.1)
                }
                previousCategory = nil
            #endif
        #endif
    }
}
