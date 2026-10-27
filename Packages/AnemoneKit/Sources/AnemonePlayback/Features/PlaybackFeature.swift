import AnemoneJellyfin

/// Something that works alongside playback without the controller knowing about it: progress
/// reports, skipping intros, Up Next, track menus. Each follows the controller's events, acts
/// through the controller, and shows its controls through `controller.accessories`, which both
/// the system player and Anemone's own overlay display.
///
/// Features are attached when the controller is built; `PlaybackController.features(for:)`
/// lists them.
@MainActor
public protocol PlaybackFeature: AnyObject {
    /// Called with each event, in order. The controller waits for each feature in turn, so a
    /// feature can finish something first, such as the stop report before the next entry
    /// starts; anything slow belongs in a task of its own.
    func handle(_ event: PlaybackEvent, in controller: PlaybackController) async
}

/// What happens while a controller plays its queue.
public enum PlaybackEvent: Sendable {
    /// A stream for the current entry was loaded. Retrying as a transcode after a failure loads
    /// it again.
    case loaded(PlaybackStream, PlaybackQueue.Entry)
    /// Playback got under way after loading.
    case started(PlaybackProgress)
    /// Once a second from `started` until `stopped`, paused or not.
    case position(PlaybackProgress)
    case paused(PlaybackProgress)
    case resumed(PlaybackProgress)
    /// The current entry played to the end. The player then closes, unless a feature played
    /// another entry while handling this or set the controller's `closesAtEnd` to `false`.
    case ended
    /// The server couldn't offer a stream, or the stream failed. A stream that failed to direct
    /// play or direct stream is retried as a transcode, so `loaded` can follow; otherwise the
    /// player shows the error.
    case failed(any Error)
    /// The loaded stream's play session is over, at this position: it ended, failed, was
    /// replaced, or the player closed. Comes once after each `loaded`.
    case stopped(Duration)
}
