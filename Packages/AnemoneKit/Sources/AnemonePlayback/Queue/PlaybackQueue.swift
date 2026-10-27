import AnemoneJellyfin

/// What a player plays, in order, and where it is: one item, an episode and those after it, or
/// what Play and Shuffle find in a series, season, collection or playlist.
public struct PlaybackQueue: Sendable {
    public struct Entry: Hashable, Sendable {
        public var itemID: MediaItem.ID
        /// Where to start; the beginning when `nil`.
        public var startPosition: Duration?
        public var metadata: PlaybackMetadata
        /// A cinema-mode intro, which plays straight into the entry after it (Phase 5c). What
        /// counts entries or moves between them passes over intros; see `next`.
        public var isIntro: Bool

        public init(
            itemID: MediaItem.ID,
            startPosition: Duration? = nil,
            metadata: PlaybackMetadata,
            isIntro: Bool = false,
        ) {
            self.itemID = itemID
            self.startPosition = startPosition
            self.metadata = metadata
            self.isIntro = isIntro
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

    /// The entry after the current one, if there is one, passing over intros: what Next, Up Next
    /// and Now Playing move on to. Intros only lead into the entry after them, which the
    /// controller plays itself (Phase 5c).
    public var next: Entry? {
        nextIndex.map { entries[$0] }
    }

    /// While an intro plays, where the entry right after it is, another intro or what was picked:
    /// the player plays it straight after the intro, or in its place when the intro won't play,
    /// so the user still gets what they picked rather than an error.
    public var afterIntroIndex: Int? {
        current.isIntro && entries.indices.contains(currentIndex + 1) ? currentIndex + 1 : nil
    }

    /// Where `next` is in `entries`.
    public var nextIndex: Int? {
        entries.indices.dropFirst(currentIndex + 1).first { !entries[$0].isIntro }
    }

    /// Where the closest entry before the current one is, passing over intros, as Previous goes
    /// back to it: an intro isn't played again once what it led into has started.
    public var previousIndex: Int? {
        entries.indices.prefix(currentIndex).last { !entries[$0].isIntro }
    }

    /// The entries after the current one, with their places in `entries`, without intros: what
    /// the player's queue row offers.
    public var upcoming: [(index: Int, entry: Entry)] {
        entries.indices.dropFirst(currentIndex + 1).compactMap { index in
            entries[index].isIntro ? nil : (index, entries[index])
        }
    }

    /// How many entries there are besides intros: what the player counts, as in "Playing 3 of 5"
    /// and Now Playing's queue.
    public var countWithoutIntros: Int {
        entries.count(where: { !$0.isIntro })
    }

    /// The current entry's place among the entries besides intros, from 0. An intro is counted
    /// at the place of the entry it leads into.
    public var indexWithoutIntros: Int {
        entries.prefix(currentIndex).count(where: { !$0.isIntro })
    }

    /// Adds entries at the end, such as the episodes after the one playing once they've loaded.
    public mutating func append(_ more: [Entry]) {
        entries += more
    }

    /// Adds entries to play before the current one, from the first of them, such as intros.
    public mutating func insertBeforeCurrent(_ more: [Entry]) {
        entries.insert(contentsOf: more, at: currentIndex)
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
