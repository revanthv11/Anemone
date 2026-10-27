import Foundation

/// What a page asks the player for: a queue, and how to play it. The player builds its
/// `PlaybackController` from it, so every page starts playback the same way.
public struct PlaybackRequest: Identifiable, Sendable {
    /// Finds entries to add after the queue's own, such as the episodes after the one picked.
    public typealias Following = @Sendable () async throws -> [PlaybackQueue.Entry]

    public let id = UUID()
    public var queue: PlaybackQueue
    /// Plays the queue in a random order, as Shuffle does.
    public var shuffles: Bool
    /// Asked once the first entry is loading, so playback starts without waiting for it, as
    /// Wholphin queues up a series after the episode it starts. When it fails, the queue stays
    /// as it is.
    public var following: Following?

    public init(queue: PlaybackQueue, shuffles: Bool = false, following: Following? = nil) {
        self.queue = queue
        self.shuffles = shuffles
        self.following = following
    }

    /// A queue of one entry.
    public init(_ entry: PlaybackQueue.Entry, following: Following? = nil) {
        self.init(queue: PlaybackQueue(entry), following: following)
    }
}
