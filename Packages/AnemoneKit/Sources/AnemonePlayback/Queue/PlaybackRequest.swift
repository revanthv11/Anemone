import Foundation

/// What a page asks the player for: a queue, and how to play it. The player builds its
/// `PlaybackController` from it, so every page starts playback the same way.
public struct PlaybackRequest: Identifiable, Sendable {
    public let id = UUID()
    public var queue: PlaybackQueue
    /// Plays the queue in a random order, as Shuffle does.
    public var shuffles: Bool

    public init(queue: PlaybackQueue, shuffles: Bool = false) {
        self.queue = queue
        self.shuffles = shuffles
    }

    /// A queue of one entry.
    public init(_ entry: PlaybackQueue.Entry) {
        self.init(queue: PlaybackQueue(entry))
    }
}
