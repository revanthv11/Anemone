import AnemoneJellyfin
import JellyfinAPI

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

    /// Called before each request for a stream, in the order features are listed, so a feature
    /// can have a say in what the server is asked, such as the audio and subtitles to send. Most
    /// features leave it as it is.
    func prepare(_ request: inout StreamRequest) async
}

public extension PlaybackFeature {
    func prepare(_: inout StreamRequest) async {}
}

/// What the controller asks the server for when it loads a stream: the parameters of Jellyfin's
/// PlaybackInfo that features can change in `prepare(_:)`.
public struct StreamRequest: Hashable, Sendable {
    public let itemID: MediaItem.ID
    /// `false` makes the server transcode, for Wholphin's retry after a failure.
    public let allowsDirect: Bool
    /// The version to play; the server's first when `nil`. A retry or a reload keeps the
    /// version playing.
    public var mediaSourceID: String?
    /// What the engine plays, as the server is told.
    public var profile: DeviceProfile
    /// The audio to send; the server's choice when `nil`.
    public var audioStreamIndex: Int?
    /// The subtitles to send, -1 for none; the server's choice when `nil`.
    public var subtitleStreamIndex: Int?

    public init(
        itemID: MediaItem.ID,
        allowsDirect: Bool,
        mediaSourceID: String? = nil,
        profile: DeviceProfile,
        audioStreamIndex: Int? = nil,
        subtitleStreamIndex: Int? = nil,
    ) {
        self.itemID = itemID
        self.allowsDirect = allowsDirect
        self.mediaSourceID = mediaSourceID
        self.profile = profile
        self.audioStreamIndex = audioStreamIndex
        self.subtitleStreamIndex = subtitleStreamIndex
    }
}

extension JellyfinSession {
    /// The stream `request` asks for, at up to `maxBitrate`: the version it names, as a retry, a
    /// reload or chosen tracks do, else the version picked on the item's page while the server
    /// still has it. The server ignores track indices sent without a version.
    func playbackStream(for request: StreamRequest, maxBitrate: Int) async throws -> PlaybackStream {
        guard let mediaSourceID = request.mediaSourceID else {
            return try await playbackStream(
                forPickedVersionOf: request.itemID,
                profile: request.profile,
                maxBitrate: maxBitrate,
                allowsDirect: request.allowsDirect,
            )
        }
        return try await playbackStream(
            for: request.itemID,
            profile: request.profile,
            maxBitrate: maxBitrate,
            allowsDirect: request.allowsDirect,
            mediaSourceID: mediaSourceID,
            audioStreamIndex: request.audioStreamIndex,
            subtitleStreamIndex: request.subtitleStreamIndex,
        )
    }
}

/// What happens while a controller plays its queue.
public enum PlaybackEvent: Sendable {
    /// A stream for the current entry was loaded. Retrying as a transcode after a failure loads
    /// it again, unless the entry was reloaded: then the retry is `reloaded` too.
    case loaded(PlaybackStream, PlaybackQueue.Entry)
    /// The current entry's stream was replaced by another, asked for with `reload()` (as for a
    /// track the stream doesn't carry), which plays on from the same position. It comes in
    /// place of `loaded`, after the replaced stream's `stopped`: it's still the same entry, so
    /// what features keep for an entry, such as segments already skipped or an Up Next that was
    /// cancelled, carries on. If playback was paused, it stays paused, and `started` comes when it
    /// resumes. A transcode retry after a reloaded stream fails comes as `reloaded` as well.
    case reloaded(PlaybackStream)
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
    /// replaced, or the player closed. Comes once after each `loaded` or `reloaded`.
    case stopped(Duration)
}
