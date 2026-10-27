import AnemoneJellyfin
@testable import AnemonePlayback
import Testing

/// The music queue's order, shuffle and repeat, following ExoPlayer's playlist as Wholphin uses it.
struct MusicQueueTests {
    private let songs = ["a", "b", "c", "d", "e"].map(MusicItem.song)

    private func ids(_ queue: MusicQueue) -> [String] {
        queue.entries.map(\.song.id)
    }

    @Test func `a queue plays its songs in order from the first`() {
        let queue = MusicQueue(songs)

        #expect(ids(queue) == ["a", "b", "c", "d", "e"])
        #expect(queue.currentIndex == 0)
        #expect(!queue.isShuffled)
        #expect(MusicQueue([]).currentIndex == nil)
    }

    @Test func `a shuffled queue plays every song once, in a random order`() {
        var generator = SplitMixGenerator(seed: 7)
        let queue = MusicQueue(songs, shuffled: true, using: &generator)

        #expect(queue.isShuffled)
        #expect(queue.currentIndex == 0)
        #expect(Set(ids(queue)) == Set(["a", "b", "c", "d", "e"]))
        #expect(ids(queue) != ["a", "b", "c", "d", "e"])
    }

    @Test func `next moves on, and stops at the end unless repeating everything`() {
        var queue = MusicQueue(songs)
        queue.move(to: 4)

        #expect(queue.nextIndex(automatic: true) == nil)
        #expect(queue.nextIndex(automatic: false) == nil)
        queue.repeatMode = .all
        #expect(queue.nextIndex(automatic: true) == 0)
        #expect(queue.nextIndex(automatic: false) == 0)
        queue.move(to: 1)
        #expect(queue.nextIndex(automatic: true) == 2)
    }

    @Test func `repeating one song replays it when it ends, but Next still moves on`() {
        var queue = MusicQueue(songs)
        queue.repeatMode = .one
        queue.move(to: 2)

        #expect(queue.nextIndex(automatic: true) == 2)
        #expect(queue.nextIndex(automatic: false) == 3)
        queue.move(to: 4)
        // ExoPlayer navigates as if repeat were off.
        #expect(queue.nextIndex(automatic: false) == nil)
    }

    @Test func `previous goes back, wrapping round only when repeating everything`() {
        var queue = MusicQueue(songs)

        #expect(queue.previousIndex == nil)
        queue.repeatMode = .all
        #expect(queue.previousIndex == 4)
        queue.move(to: 3)
        #expect(queue.previousIndex == 2)
    }

    @Test func `the repeat button cycles off, all, one`() {
        #expect(MusicQueue.RepeatMode.off.next == .all)
        #expect(MusicQueue.RepeatMode.all.next == .one)
        #expect(MusicQueue.RepeatMode.one.next == .off)
    }

    @Test func `shuffling keeps the song playing and shuffles what comes after it`() {
        var queue = MusicQueue(songs)
        queue.move(to: 1)
        var generator = SplitMixGenerator(seed: 3)

        queue.setShuffled(true, using: &generator)

        #expect(queue.isShuffled)
        #expect(queue.currentIndex == 1)
        #expect(Array(ids(queue).prefix(2)) == ["a", "b"])
        #expect(Set(ids(queue).dropFirst(2)) == Set(["c", "d", "e"]))
    }

    @Test func `unshuffling puts the songs back in order, still on the same song`() {
        var generator = SplitMixGenerator(seed: 11)
        var queue = MusicQueue(songs, shuffled: true, using: &generator)
        queue.move(to: 3)
        let playing = queue.current?.song.id

        queue.setShuffled(false, using: &generator)

        #expect(!queue.isShuffled)
        #expect(ids(queue) == ["a", "b", "c", "d", "e"])
        #expect(queue.current?.song.id == playing)
    }

    @Test func `play next goes straight after the current song, and stays there unshuffled`() {
        var generator = SplitMixGenerator(seed: 5)
        var queue = MusicQueue(songs, shuffled: true, using: &generator)
        queue.move(to: 2)
        let playing = queue.current?.song.id

        queue.insertNext([.song("x"), .song("y")])

        #expect(Array(ids(queue)[3 ... 4]) == ["x", "y"])
        #expect(queue.current?.song.id == playing)
        queue.setShuffled(false, using: &generator)
        let order = ids(queue)
        let after = order.firstIndex(of: playing ?? "")
        #expect(after.map { Array(order[($0 + 1) ... ($0 + 2)]) } == ["x", "y"])
        #expect(order.count == 7)
    }

    @Test func `added songs go last, shuffled or not`() {
        var generator = SplitMixGenerator(seed: 9)
        var queue = MusicQueue(songs, shuffled: true, using: &generator)

        queue.append([.song("z")])

        #expect(ids(queue).last == "z")
        queue.setShuffled(false, using: &generator)
        #expect(ids(queue) == ["a", "b", "c", "d", "e", "z"])
        var empty = MusicQueue()
        empty.append([.song("z")])
        #expect(empty.currentIndex == 0)
    }

    @Test func `the same song can be queued twice`() {
        var queue = MusicQueue([.song("a")])
        queue.append([.song("a")])

        #expect(ids(queue) == ["a", "a"])
        #expect(Set(queue.entries.map(\.id)).count == 2)
        #expect(queue.contains("a"))
        #expect(!queue.contains("b"))
    }

    @Test func `moving an entry keeps the current song, and becomes the order unshuffled`() {
        var queue = MusicQueue(songs)
        queue.move(to: 1)

        queue.moveEntry(from: 4, to: 0)

        #expect(ids(queue) == ["e", "a", "b", "c", "d"])
        #expect(queue.current?.song.id == "b")
        queue.setShuffled(true)
        queue.setShuffled(false)
        #expect(ids(queue) == ["e", "a", "b", "c", "d"])
    }

    @Test func `removing the current song makes the next current, or the last when it was last`() {
        var queue = MusicQueue(songs)
        queue.move(to: 2)

        var changed = queue.remove(at: 0)
        #expect(!changed)
        #expect(queue.current?.song.id == "c")
        changed = queue.remove(at: 3)
        #expect(!changed)
        #expect(ids(queue) == ["b", "c", "d"])
        changed = queue.remove(at: 1)
        #expect(changed)
        #expect(queue.current?.song.id == "d")
        changed = queue.remove(at: 1)
        #expect(changed)
        #expect(queue.current?.song.id == "b")
        changed = queue.remove(at: 0)
        #expect(changed)
        #expect(queue.isEmpty)
        #expect(queue.currentIndex == nil)
    }
}

extension MusicItem {
    /// A song with only an ID and a title.
    static func song(_ id: String) -> MusicItem {
        MusicItem(details: ItemDetails(item: MediaItem(id: id, name: "Song \(id)", kind: .audio)))
    }
}

/// SplitMix64, so shuffles repeat from one run to the next.
private struct SplitMixGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
