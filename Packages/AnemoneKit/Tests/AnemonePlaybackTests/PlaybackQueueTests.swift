@testable import AnemonePlayback
import Testing

/// Queues, requests and the accessories features show.
@MainActor
struct PlaybackQueueTests {
    @Test func `a queue of one has nothing next`() {
        let queue = PlaybackQueue(.item("m1", from: .seconds(5)))

        #expect(queue.entries == [.item("m1", from: .seconds(5))])
        #expect(queue.current == .item("m1", from: .seconds(5)))
        #expect(queue.next == nil)
        #expect(PlaybackRequest(.item("m1")).queue.entries.count == 1)
        #expect(PlaybackRequest(.item("m1")).shuffles == false)
    }

    @Test func `a queue needs something to play`() {
        #expect(PlaybackQueue(entries: []) == nil)
        #expect(PlaybackQueue(entries: [.item("e1")], startingAt: 1) == nil)
        #expect(PlaybackQueue(entries: [.item("e1"), .item("e2")], startingAt: 1)?.current == .item("e2"))
    }

    @Test func `shuffling keeps every entry and starts from the first`() throws {
        var queue = try #require(PlaybackQueue(entries: (1 ... 10).map { .item("e\($0)") }, startingAt: 4))
        var generator = SeededGenerator()

        queue.shuffle(using: &generator)

        #expect(queue.currentIndex == 0)
        #expect(Set(queue.entries.map(\.itemID)) == Set((1 ... 10).map { "e\($0)" }))
    }

    @Test func `showing an accessory again replaces it`() {
        let accessories = PlayerAccessories()

        accessories.show(PlayerAction(id: "skip", title: "Skip Intro") {})
        accessories.show(PlayerAction(id: "next", title: "Next Episode") {})
        accessories.show(PlayerAction(id: "skip", title: "Skip Recap") {})
        accessories.show(PlayerMenu(id: "speed", title: "Speed", options: []))
        accessories.removeAction("next")

        #expect(accessories.actions.map(\.title) == ["Skip Recap"])
        #expect(accessories.menus.map(\.id) == ["speed"])
    }

    @Test func `a feature dismisses only its own card`() {
        let accessories = PlayerAccessories()
        accessories.show(PlayerCard(id: "upNext", title: "Up Next", actions: []))

        accessories.dismissCard("stillWatching")
        #expect(accessories.card?.id == "upNext")
        accessories.dismissCard("upNext")
        #expect(accessories.card == nil)
    }
}

/// The same numbers every run.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64 = 42

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}
