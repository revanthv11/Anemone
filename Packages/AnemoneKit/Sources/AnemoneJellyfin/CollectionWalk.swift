import Foundation

/// What a walk through a collection's page has queued so far, for
/// `JellyfinSession.collectionQueue(following:of:filter:)`.
struct CollectionWalk {
    private(set) var items: [ItemDetails] = []
    /// What's been queued or gone into, so each counts once.
    private var seen: Set<MediaItem.ID>
    /// What the walk can't queue: items listed that aren't videos, such as music or an album,
    /// and collections too deep inside to go into.
    private var leftOut: Set<MediaItem.ID> = []

    /// A walk through `collection`'s page, which it never goes into again from inside.
    init(collection: MediaItem.ID) {
        seen = [collection]
    }

    /// How many more videos fit in the queue.
    var room: Int {
        JellyfinSession.queueLimit - items.count
    }

    var isFull: Bool {
        room <= 0
    }

    /// How many items it left out, each once, not counting a collection gone into after all
    /// from a place less deep.
    var leftOutCount: Int {
        leftOut.subtracting(seen).count
    }

    func hasSeen(_ id: MediaItem.ID) -> Bool {
        seen.contains(id)
    }

    /// Whether a series, season or collection is new to the walk, to go into.
    mutating func enter(_ id: MediaItem.ID) -> Bool {
        seen.insert(id).inserted
    }

    mutating func leaveOut(_ id: MediaItem.ID) {
        leftOut.insert(id)
    }

    mutating func add(_ videos: [ItemDetails]) {
        for video in videos where !isFull && seen.insert(video.id).inserted {
            items.append(video)
        }
    }
}
