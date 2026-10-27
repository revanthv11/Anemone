import Foundation
import JellyfinAPI

/// A song's engine, which keeps a song the user paused from starting on its own.
///
/// `PlaybackController` plays its engine as soon as a stream is ready, as a video should. A song
/// paused while it loaded, or skipped to while paused, waits here instead, paused and ready,
/// until the user resumes it. A transcode tried again after a failure waits the same way.
@MainActor
final class SongEngine: PlayerEngine {
    let base: any PlayerEngine
    /// Whether the music is paused, so the song mustn't start.
    private let isHeld: @MainActor () -> Bool
    /// Whether the loaded stream is ready: the controller has asked it to play since it loaded.
    private(set) var isReady = false

    init(_ base: any PlayerEngine, isHeld: @escaping @MainActor () -> Bool) {
        self.base = base
        self.isHeld = isHeld
    }

    var deviceProfile: DeviceProfile {
        base.deviceProfile
    }

    var videoOutput: PlayerVideoOutput {
        base.videoOutput
    }

    var currentTime: Duration {
        base.currentTime
    }

    var duration: Duration? {
        base.duration
    }

    var rate: Float {
        get { base.rate }
        set { base.rate = newValue }
    }

    func load(_ url: URL, from position: Duration?, metadata: PlaybackMetadata) -> AsyncStream<PlayerEvent> {
        isReady = false
        return base.load(url, from: position, metadata: metadata)
    }

    /// The controller asks once the stream is ready; the song plays unless the music is paused.
    func play() {
        isReady = true
        if !isHeld() {
            base.play()
        }
    }

    func pause() {
        base.pause()
    }

    func stop() {
        base.stop()
    }

    func seek(to position: Duration) async -> Bool {
        await base.seek(to: position)
    }

    func tracks(_ kind: PlayerTrack.Kind) async -> [PlayerTrack] {
        await base.tracks(kind)
    }

    func select(_ track: PlayerTrack?, _ kind: PlayerTrack.Kind) async {
        await base.select(track, kind)
    }
}
