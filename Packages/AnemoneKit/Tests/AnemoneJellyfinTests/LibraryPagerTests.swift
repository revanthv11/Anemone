import AnemoneJellyfin
import Foundation
import Synchronization
import Testing

@MainActor
struct LibraryPagerTests {
    /// A fake library of `count` items that records which pages were asked for.
    private final class FakeLibrary: Sendable {
        let count: Int
        /// Counted, but left out of their pages, as items removed since the count are, or those
        /// that can't be read.
        let missing: Set<Int>
        let requests = Mutex<[Int]>([])
        let failures = Mutex<Set<Int>>([])

        init(count: Int, missing: Set<Int> = []) {
            self.count = count
            self.missing = missing
        }

        func load(startIndex: Int, limit: Int, includeTotalCount: Bool) throws -> LibraryPage {
            requests.withLock { $0.append(startIndex) }
            if failures.withLock({ $0.remove(startIndex) }) != nil {
                throw URLError(.timedOut)
            }
            let items = (startIndex ..< min(startIndex + limit, count)).filter { !missing.contains($0) }.map { index in
                LibraryEntry(item: MediaItem(id: "i\(index)", name: "Item \(index)", kind: .movie), sortName: nil)
            }
            return LibraryPage(items: items, totalCount: includeTotalCount ? count : nil)
        }
    }

    private func pager(_ library: FakeLibrary, pageSize: Int = 100) -> LibraryPager {
        LibraryPager(pageSize: pageSize) { startIndex, limit, includeTotalCount in
            try library.load(startIndex: startIndex, limit: limit, includeTotalCount: includeTotalCount)
        }
    }

    @Test func `starts with the first page and the total count`() async throws {
        let library = FakeLibrary(count: 5000)
        let pager = pager(library)

        try await pager.start()

        #expect(pager.count == 5000)
        #expect(pager.item(at: 0)?.id == "i0")
        #expect(pager.item(at: 99)?.id == "i99")
        #expect(pager.item(at: 100) == nil)
        #expect(library.requests.withLock { $0 } == [0])
    }

    @Test func `loads the next page once focus passes the middle of the current one`() async throws {
        let library = FakeLibrary(count: 5000)
        let pager = pager(library)
        try await pager.start()

        await pager.prefetch(around: 30)
        #expect(library.requests.withLock { $0 } == [0])

        await pager.prefetch(around: 50)
        #expect(library.requests.withLock { $0 } == [0, 100])
        #expect(pager.item(at: 150)?.id == "i150")
        #expect(pager.item(at: 200) == nil)
    }

    @Test func `asks for each page once, even when several cards ask together`() async throws {
        let library = FakeLibrary(count: 5000)
        let pager = pager(library)
        try await pager.start()

        async let first: Void = pager.prefetch(around: 2510)
        async let second: Void = pager.prefetch(around: 2520)
        _ = await (first, second)
        await pager.prefetch(around: 2530)

        #expect(library.requests.withLock { $0 } == [0, 2500])
        #expect(pager.item(at: 2599)?.id == "i2599")
    }

    @Test func `loads a far page directly for a jump`() async throws {
        let library = FakeLibrary(count: 5000)
        let pager = pager(library)
        try await pager.start()

        let item = try await pager.load(at: 4321)

        #expect(item?.id == "i4321")
        #expect(library.requests.withLock { $0 } == [0, 4300])
    }

    @Test func `doesn't ask for pages past the end`() async throws {
        let library = FakeLibrary(count: 120)
        let pager = pager(library)
        try await pager.start()

        await pager.prefetch(around: 119)

        #expect(library.requests.withLock { $0 } == [0, 100])
        #expect(pager.item(at: 119)?.id == "i119")
        #expect(pager.item(at: 120) == nil)
    }

    @Test func `retries a page that failed the next time a card asks for it`() async throws {
        let library = FakeLibrary(count: 5000)
        library.failures.withLock { $0 = [200] }
        let pager = pager(library)
        try await pager.start()

        await pager.prefetch(around: 210)
        #expect(pager.item(at: 210) == nil)
        #expect(pager.error != nil)

        await pager.prefetch(around: 211)
        #expect(pager.item(at: 211)?.id == "i211")
        #expect(pager.error == nil)
        #expect(library.requests.withLock { $0 } == [0, 200, 200])
    }

    @Test func `pages that come back short close up, so every place gets an item`() async throws {
        let missing: Set = [3, 50, 99, 140, 260]
        let library = FakeLibrary(count: 300, missing: missing)
        let pager = pager(library)

        try await pager.start()
        // The first page left out three of the hundred it counted.
        #expect(pager.count == 297)
        #expect(pager.item(at: 96)?.id == "i98")
        // The second page starts here now, and isn't in yet.
        #expect(pager.item(at: 97) == nil)

        var shown: [MediaItem.ID] = []
        var index = 0
        while index < pager.count {
            try shown.append(#require(await pager.load(at: index)).id)
            index += 1
        }

        #expect(pager.count == 295)
        #expect(shown == (0 ..< 300).filter { !missing.contains($0) }.map { "i\($0)" })
        #expect(library.requests.withLock { $0 } == [0, 100, 200])
    }

    @Test func `a jump past a page that comes back short lands on the item now there`() async throws {
        // The second page lost 60 of its hundred since the count.
        let library = FakeLibrary(count: 300, missing: Set(100 ..< 160))
        let pager = pager(library)
        try await pager.start()

        let item = try await pager.load(at: 150)

        // Place 150 was on the second page, which closed up to 40; it's now the third page's
        // eleventh item.
        #expect(item?.id == "i210")
        #expect(pager.count == 240)
        #expect(library.requests.withLock { $0 } == [0, 100, 200])
    }

    @Test func `cards past a page that came back short ask for the page they're now on`() async throws {
        let library = FakeLibrary(count: 300, missing: Set(100 ..< 180))
        let pager = pager(library)
        try await pager.start()

        // Before the second page is in, card 130 is on it, and not past its middle.
        await pager.prefetch(around: 130)

        #expect(pager.count == 220)
        #expect(pager.item(at: 130)?.id == "i210")
        #expect(library.requests.withLock { $0 } == [0, 100, 200])
    }

    @Test func `a page that comes back empty is passed over`() async throws {
        let library = FakeLibrary(count: 250, missing: Set(100 ..< 200))
        let pager = pager(library)
        try await pager.start()

        let item = try await pager.load(at: 100)

        #expect(item?.id == "i200")
        #expect(pager.count == 150)
        #expect(pager.item(at: 149)?.id == "i249")
        #expect(pager.item(at: 150) == nil)
    }
}
