import AnemoneJellyfin

/// The songs the music player plays, in the order it plays them, with Wholphin's shuffle and
/// repeat modes. Wholphin leaves this to ExoPlayer's playlist; this follows it, except that
/// turning shuffle on keeps the playing song and shuffles what comes after it, and the order
/// shown is the order they'll play.
public struct MusicQueue: Sendable {
    /// ExoPlayer's repeat modes, which Wholphin's repeat button cycles through.
    public enum RepeatMode: String, CaseIterable, Sendable {
        case off
        /// Starts again from the first song after the last.
        case all
        /// Plays the song again when it ends. Next and Previous still move, as in ExoPlayer.
        case one

        /// The button's next mode: off, all, one, off.
        public var next: RepeatMode {
            switch self {
            case .off: .all
            case .all: .one
            case .one: .off
            }
        }
    }

    public struct Entry: Hashable, Identifiable, Sendable {
        /// Tells apart the same song queued twice.
        public let id: Int
        public let song: MusicItem
        /// Where the entry goes when shuffle is turned off.
        fileprivate var rank: Int
    }

    /// In the order they play.
    public private(set) var entries: [Entry] = []
    /// The entry playing or about to; `nil` when the queue is empty.
    public private(set) var currentIndex: Int?
    public private(set) var isShuffled = false
    public var repeatMode = RepeatMode.off
    private var nextID = 0

    public init() {}

    /// A queue of `songs` from the first, or in a random order when `shuffled`, as Wholphin's
    /// Play and Shuffle buttons start it.
    public init(_ songs: [MusicItem], shuffled: Bool = false, using generator: inout some RandomNumberGenerator) {
        append(songs)
        if shuffled, !entries.isEmpty {
            isShuffled = true
            entries.shuffle(using: &generator)
        }
        currentIndex = entries.isEmpty ? nil : 0
    }

    public init(_ songs: [MusicItem], shuffled: Bool = false) {
        var generator = SystemRandomNumberGenerator()
        self.init(songs, shuffled: shuffled, using: &generator)
    }

    public var current: Entry? {
        currentIndex.map { entries[$0] }
    }

    public var isEmpty: Bool {
        entries.isEmpty
    }

    /// Where to go after the current entry: when it ends on its own (`automatic`), or on Next.
    /// Like ExoPlayer, repeating one song only repeats it when it ends; Next moves on as if
    /// repeat were off. `nil` at the end of the queue.
    public func nextIndex(automatic: Bool) -> Int? {
        guard let currentIndex else { return nil }
        if automatic, repeatMode == .one {
            return currentIndex
        }
        if currentIndex + 1 < entries.count {
            return currentIndex + 1
        }
        return repeatMode == .all ? 0 : nil
    }

    /// The entry before the current one, wrapping round when repeating everything. `nil` at the
    /// start, where Previous restarts the song instead.
    public var previousIndex: Int? {
        guard let currentIndex else { return nil }
        if currentIndex > 0 {
            return currentIndex - 1
        }
        return repeatMode == .all && entries.count > 1 ? entries.count - 1 : nil
    }

    /// Makes the entry at `index` the current one.
    public mutating func move(to index: Int) {
        guard entries.indices.contains(index) else { return }
        currentIndex = index
    }

    /// Turning shuffle on puts what comes after the current song in a random order; turning it
    /// off puts everything back in its own order, still on the same song.
    public mutating func setShuffled(_ shuffled: Bool, using generator: inout some RandomNumberGenerator) {
        guard shuffled != isShuffled else { return }
        isShuffled = shuffled
        guard let currentIndex else { return }
        if shuffled {
            entries[(currentIndex + 1)...].shuffle(using: &generator)
        } else {
            let currentID = entries[currentIndex].id
            entries.sort { $0.rank < $1.rank }
            self.currentIndex = entries.firstIndex { $0.id == currentID }
        }
    }

    public mutating func setShuffled(_ shuffled: Bool) {
        var generator = SystemRandomNumberGenerator()
        setShuffled(shuffled, using: &generator)
    }

    /// Adds songs at the end, as Wholphin's "Add to queue" does. They go last whether or not the
    /// queue is shuffled.
    public mutating func append(_ songs: [MusicItem]) {
        let firstRank = (entries.map(\.rank).max() ?? -1) + 1
        entries += songs.enumerated().map { offset, song in makeEntry(song, rank: firstRank + offset) }
        if currentIndex == nil, !entries.isEmpty {
            currentIndex = 0
        }
    }

    /// Wholphin's "Play next": the songs go straight after the current one, and stay there when
    /// shuffle is turned off.
    public mutating func insertNext(_ songs: [MusicItem]) {
        guard let currentIndex else {
            append(songs)
            return
        }
        let afterRank = entries[currentIndex].rank
        for index in entries.indices where entries[index].rank > afterRank {
            entries[index].rank += songs.count
        }
        let inserted = songs.enumerated().map { offset, song in makeEntry(song, rank: afterRank + 1 + offset) }
        entries.insert(contentsOf: inserted, at: currentIndex + 1)
    }

    /// Moves an entry, as Wholphin's queue move buttons do. Unshuffled, the move is kept as the
    /// queue's own order.
    public mutating func moveEntry(from source: Int, to destination: Int) {
        guard entries.indices.contains(source), entries.indices.contains(destination), source != destination else {
            return
        }
        let currentID = current?.id
        let entry = entries.remove(at: source)
        entries.insert(entry, at: destination)
        if !isShuffled {
            for index in entries.indices {
                entries[index].rank = index
            }
        }
        currentIndex = currentID.flatMap { id in entries.firstIndex { $0.id == id } }
    }

    /// Removes an entry. Removing the current one makes the entry after it current, or the last
    /// one when it was last.
    ///
    /// - Returns: whether the current entry changed, so the player plays the new one.
    @discardableResult
    public mutating func remove(at index: Int) -> Bool {
        guard entries.indices.contains(index), let currentIndex else { return false }
        entries.remove(at: index)
        if entries.isEmpty {
            self.currentIndex = nil
            return true
        }
        if index < currentIndex {
            self.currentIndex = currentIndex - 1
            return false
        }
        if index == currentIndex {
            self.currentIndex = min(currentIndex, entries.count - 1)
            return true
        }
        return false
    }

    /// Whether a song is queued, for the marks on song lists.
    public func contains(_ songID: MediaItem.ID) -> Bool {
        entries.contains { $0.song.id == songID }
    }

    private mutating func makeEntry(_ song: MusicItem, rank: Int) -> Entry {
        defer { nextID += 1 }
        return Entry(id: nextID, song: song, rank: rank)
    }
}
