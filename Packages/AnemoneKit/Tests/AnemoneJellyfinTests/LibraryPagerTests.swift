import AnemoneJellyfin
import Foundation
import Synchronization
import Testing

@MainActor
struct LibraryPagerTests {
    /// A fake library of `count` items that records which pages were asked for.
    private final class FakeLibrary: Sendable {
        let count: Int
        let requests = Mutex<[Int]>([])
        let failures = Mutex<Set<Int>>([])

        init(count: Int) {
            self.count = count
        }

        func load(startIndex: Int, limit: Int, includeTotalCount: Bool) throws -> LibraryPage {
            requests.withLock { $0.append(startIndex) }
            if failures.withLock({ $0.remove(startIndex) }) != nil {
                throw URLError(.timedOut)
            }
            let items = (startIndex ..< min(startIndex + limit, count)).map { index in
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
}
