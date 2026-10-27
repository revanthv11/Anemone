@testable import AnemoneJellyfin
import Foundation
import Synchronization
import Testing

/// Every page of a list of IDs, for a random grid or slideshow to shuffle: the first page alone,
/// with the count, then the rest a few at a time.
@MainActor
struct LibraryIDPagesTests {
    @Test func `the pages after the first go out four at a time, not one after another`() async throws {
        let list = HeldList(count: 5500)
        let fetch = Task { try await list.allPages() }

        // The first page alone, which counts the list.
        #expect(await eventually { list.state.arrived == [0] })
        #expect(list.state.counted == [0])
        list.release(0)
        // Then four together, while none of them has come back.
        #expect(await eventually { list.state.arrived.count == 5 })
        #expect(Set(list.state.arrived.dropFirst()) == [1000, 2000, 3000, 4000])
        for _ in 0 ..< 50 {
            await Task.yield()
        }
        #expect(list.state.arrived.count == 5)
        // As one comes back, the last goes out.
        list.release(2000)
        #expect(await eventually { list.state.arrived.count == 6 })
        #expect(list.state.arrived.last == 5000)
        list.releaseAll()

        let pages = try await fetch.value
        #expect(pages.map(\.count) == [1000, 1000, 1000, 1000, 1000, 500])
        #expect(Array(pages.joined()) == Array(0 ..< 5500))
        #expect(list.state.mostAtOnce == 4)
        #expect(list.state.counted == [0])
    }

    @Test func `pages past the count, added meanwhile, follow one at a time until a short one`() async throws {
        // Counted at 2000, but 500 more came after the first page.
        let list = HeldList(count: 2500, countSaid: 2000)
        list.releaseAll()

        let pages = try await list.allPages()

        #expect(pages.map(\.count) == [1000, 1000, 500])
        #expect(list.state.arrived == [0, 1000, 2000])
    }

    @Test func `without a count, every page follows the one before`() async throws {
        let list = HeldList(count: 2100, countSaid: nil)
        list.releaseAll()

        let pages = try await list.allPages()

        #expect(pages.map(\.count) == [1000, 1000, 100])
        #expect(list.state.arrived == [0, 1000, 2000])
        #expect(list.state.mostAtOnce == 1)
    }

    @Test func `a short first page is the whole list`() async throws {
        let list = HeldList(count: 40)
        list.releaseAll()

        let pages = try await list.allPages()

        #expect(pages == [Array(0 ..< 40)])
        #expect(list.state.arrived == [0])
    }
}

/// A list of `count` numbers, paged, whose pages wait until the test releases them, noting how
/// many are out at once.
private final class HeldList: Sendable {
    struct State {
        var arrived: [Int] = []
        var counted: [Int] = []
        var released: Set<Int> = []
        var releasesAll = false
        var waiting: [Int: CheckedContinuation<Void, Never>] = [:]
        var out = 0
        var mostAtOnce = 0
    }

    private let count: Int
    /// What the first page says the count is; `nil` for a server that doesn't say.
    private let countSaid: Int?
    private let locked = Mutex(State())

    init(count: Int) {
        self.count = count
        countSaid = count
    }

    init(count: Int, countSaid: Int?) {
        self.count = count
        self.countSaid = countSaid
    }

    var state: State {
        locked.withLock(\.self)
    }

    /// Every page, as `JellyfinSession.allPages` fetches a list's IDs: a thousand at a time,
    /// four at once.
    func allPages() async throws -> [[Int]] {
        try await JellyfinSession.allPages(size: 1000, width: 4) { startIndex, counts in
            (startIndex, counts)
        } fetch: { [self] request in
            await page(from: request.0, size: 1000, counts: request.1)
        }
    }

    func page(from startIndex: Int, size: Int, counts: Bool) async -> (items: [Int], count: Int?) {
        locked.withLock { state in
            state.arrived.append(startIndex)
            if counts {
                state.counted.append(startIndex)
            }
            state.out += 1
            state.mostAtOnce = max(state.mostAtOnce, state.out)
        }
        await withCheckedContinuation { continuation in
            let isReleased = locked.withLock { state in
                if state.releasesAll || state.released.contains(startIndex) {
                    return true
                }
                state.waiting[startIndex] = continuation
                return false
            }
            if isReleased {
                continuation.resume()
            }
        }
        locked.withLock { $0.out -= 1 }
        return (Array(startIndex ..< min(startIndex + size, count)), counts ? countSaid : nil)
    }

    func release(_ startIndex: Int) {
        let waiting = locked.withLock { state in
            state.released.insert(startIndex)
            return state.waiting.removeValue(forKey: startIndex)
        }
        waiting?.resume()
    }

    func releaseAll() {
        let waiting = locked.withLock { state in
            state.releasesAll = true
            defer { state.waiting = [:] }
            return Array(state.waiting.values)
        }
        for continuation in waiting {
            continuation.resume()
        }
    }
}

/// Whether `condition` holds within `timeout`, checking every millisecond.
@MainActor
private func eventually(timeout: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else { return false }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return true
}
