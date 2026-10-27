import AnemoneJellyfin
import Foundation
import Synchronization
import Testing

/// Items deleted from the app leaving a grid that's already loaded, without loading it again.
@MainActor
struct LibraryPagerDeletionTests {
    /// A fake library whose items can be deleted, which moves those after them up the list, as
    /// on the server.
    private final class ShrinkingLibrary: Sendable {
        let indices: Mutex<[Int]>
        let requests = Mutex<[Int]>([])

        init(count: Int) {
            indices = Mutex(Array(0 ..< count))
        }

        func delete(_ index: Int) {
            indices.withLock { $0.removeAll { $0 == index } }
        }

        func load(startIndex: Int, limit: Int, includeTotalCount: Bool) -> LibraryPage {
            requests.withLock { $0.append(startIndex) }
            let all = indices.withLock { $0 }
            let items = all.dropFirst(startIndex).prefix(limit).map { index in
                LibraryEntry(item: MediaItem(id: "i\(index)", name: "Item \(index)", kind: .movie), sortName: nil)
            }
            return LibraryPage(items: Array(items), totalCount: includeTotalCount ? all.count : nil)
        }
    }

    private func pager(_ library: ShrinkingLibrary) -> LibraryPager {
        LibraryPager(pageSize: 100) { startIndex, limit, includeTotalCount in
            library.load(startIndex: startIndex, limit: limit, includeTotalCount: includeTotalCount)
        }
    }

    /// Every item, loading each page as a grid scrolled to the end would.
    private func everything(in pager: LibraryPager) async throws -> [MediaItem.ID] {
        var shown: [MediaItem.ID] = []
        var index = 0
        while index < pager.count {
            try shown.append(#require(await pager.load(at: index)).id)
            index += 1
        }
        return shown
    }

    @Test func `a deleted item leaves the grid, which closes up and counts one fewer`() async throws {
        let library = ShrinkingLibrary(count: 250)
        let pager = pager(library)
        try await pager.start()

        library.delete(5)
        pager.remove(["i5"])

        #expect(pager.count == 249)
        #expect(pager.item(at: 4)?.id == "i4")
        #expect(pager.item(at: 5)?.id == "i6")
        #expect(pager.item(at: 98)?.id == "i99")
        // The second page starts a place earlier now, and isn't in yet.
        #expect(pager.item(at: 99) == nil)
    }

    @Test func `the pages after a deletion are asked for where the server has them now`() async throws {
        let library = ShrinkingLibrary(count: 250)
        let pager = pager(library)
        try await pager.start()

        library.delete(5)
        pager.remove(["i5"])
        let shown = try await everything(in: pager)

        // Item 100, which the server moved up onto the first page, isn't skipped.
        #expect(shown == (0 ..< 250).filter { $0 != 5 }.map { "i\($0)" })
        #expect(library.requests.withLock { $0 } == [0, 99, 199])
        #expect(pager.count == 249)
    }

    @Test func `deletions on pages loaded already close them up and move the later ones`() async throws {
        let library = ShrinkingLibrary(count: 350)
        let pager = pager(library)
        try await pager.start()
        _ = try await pager.load(at: 150)

        for index in [0, 150, 199] {
            library.delete(index)
        }
        pager.remove(["i0", "i150", "i199"])

        #expect(pager.count == 347)
        #expect(pager.item(at: 0)?.id == "i1")
        #expect(pager.item(at: 148)?.id == "i149")
        #expect(pager.item(at: 149)?.id == "i151")
        #expect(pager.item(at: 196)?.id == "i198")
        #expect(pager.item(at: 197) == nil)
        let shown = try await everything(in: pager)
        #expect(shown == (0 ..< 350).filter { ![0, 150, 199].contains($0) }.map { "i\($0)" })
        #expect(library.requests.withLock { $0 } == [0, 100, 197, 297])
    }

    @Test func `an item that isn't in the grid changes nothing`() async throws {
        let library = ShrinkingLibrary(count: 250)
        let pager = pager(library)
        try await pager.start()

        pager.remove(["elsewhere"])

        #expect(pager.count == 250)
        let shown = try await everything(in: pager)
        #expect(shown == (0 ..< 250).map { "i\($0)" })
        #expect(library.requests.withLock { $0 } == [0, 100, 200])
    }

    @Test func `an item deleted from a page not loaded yet is left out when it loads`() async throws {
        let library = ShrinkingLibrary(count: 250)
        let pager = pager(library)
        try await pager.start()

        // Deleted from Search, say: the grid hasn't reached it.
        library.delete(180)
        pager.remove(["i180"])
        #expect(pager.count == 250)

        let shown = try await everything(in: pager)
        // The last page comes back a place short and closes up.
        #expect(shown == (0 ..< 250).filter { $0 != 180 }.map { "i\($0)" })
        #expect(pager.count == 249)
    }
}
