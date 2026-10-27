import AnemoneJellyfin

/// What a player plays, in order, and where it is: one item, an episode and those after it, or
/// what Play and Shuffle find in a series, season, collection or playlist.
public struct PlaybackQueue: Sendable {
    public struct Entry: Hashable, Sendable {
        public var itemID: MediaItem.ID
        /// Where to start; the beginning when `nil`.
        public var startPosition: Duration?
        public var metadata: PlaybackMetadata

        public init(itemID: MediaItem.ID, startPosition: Duration? = nil, metadata: PlaybackMetadata) {
            self.itemID = itemID
            self.startPosition = startPosition
            self.metadata = metadata
        }
    }

    /// Never empty.
    public private(set) var entries: [Entry]
    /// The entry playing, or about to. `PlaybackController` moves it.
    public internal(set) var currentIndex: Int
    /// How many items the queue was built without because they can't play here, such as music
    /// in a playlist of videos, so the player can say so.
    public var skippedCount = 0
    /// How many items the queue was built without because there were more than a queue holds
    /// (`JellyfinSession.queueLimit`, as in Wholphin), such as in a large collection, so the
    /// player can say so.
    public var overLimitCount = 0

    /// A queue of `entry` alone.
    public init(_ entry: Entry) {
        entries = [entry]
        currentIndex = 0
    }

    /// `nil` when there's nothing to play.
    public init?(entries: [Entry], startingAt index: Int = 0) {
        guard entries.indices.contains(index) else { return nil }
        self.entries = entries
        currentIndex = index
    }

    public var current: Entry {
        entries[currentIndex]
    }

    /// The entry after the current one, if there is one.
    public var next: Entry? {
        entries.indices.contains(currentIndex + 1) ? entries[currentIndex + 1] : nil
    }

    /// Adds entries at the end, such as the episodes after the one playing once they've loaded.
    public mutating func append(_ more: [Entry]) {
        entries += more
    }

    /// Puts the entries in a random order, to play from the first.
    public mutating func shuffle(using generator: inout some RandomNumberGenerator) {
        entries.shuffle(using: &generator)
        currentIndex = 0
    }

    public mutating func shuffle() {
        var generator = SystemRandomNumberGenerator()
        shuffle(using: &generator)
    }
}
