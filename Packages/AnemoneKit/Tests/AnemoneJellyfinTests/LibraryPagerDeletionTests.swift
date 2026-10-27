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

    // MARK: Random grids

    /// A fake server's movies, which can be deleted, for a grid sorted at random: `/Items` lists
    /// their IDs a page at a time, or sends those asked for by ID that it still has.
    private final class DeletableMovies: Sendable {
        let sent = Recorder()
        let all: [MediaItem.ID]
        private let deleted = Mutex<Set<MediaItem.ID>>([])

        init(host: String, count: Int) {
            all = (0 ..< count).map { "m\($0)" }
            MockServer.register(host: host) { [self] request in
                let query = sent.record(request).query
                let gone = deleted.withLock(\.self)
                let ids: [MediaItem.ID]
                if let asked = query["ids"] {
                    ids = asked.split(separator: ",").map(String.init).filter { !gone.contains($0) }
                } else {
                    let start = Int(query["startIndex"] ?? "") ?? 0
                    let limit = Int(query["limit"] ?? "") ?? all.count
                    ids = Array(all.filter { !gone.contains($0) }.dropFirst(start).prefix(limit))
                }
                let items = ids.map { #"{"Id":"\#($0)","Name":"Movie \#($0)","Type":"Movie"}"# }
                return .json(#"{"Items":[\#(items.joined(separator: ","))],"TotalRecordCount":\#(ids.count)}"#)
            }
        }

        func delete(_ id: MediaItem.ID) {
            deleted.withLock { _ = $0.insert(id) }
        }

        /// How many IDs each page of the grid asked for, in order.
        var pageSizesAsked: [Int] {
            sent.requests.compactMap { $0.query["ids"]?.split(separator: ",").count }
        }
    }

    private func randomGrid(host: String) throws -> LibraryPager {
        let query = LibraryQuery(library: Library(id: "lib", name: "Movies", kind: .movies), sort: LibrarySort(.random))
        return try LibraryPager(pageSize: 100, loader: librarySession(host: host).libraryLoader(for: query))
    }

    @Test func `a random grid asks for the same pages after a deletion, so no title shows twice`() async throws {
        let movies = DeletableMovies(host: "random-delete.test", count: 250)
        let pager = try randomGrid(host: "random-delete.test")
        try await pager.start()
        let deleted = try #require(pager.item(at: 5)).id
        let lastOnFirstPage = try #require(pager.item(at: 99)).id

        movies.delete(deleted)
        pager.remove([deleted])
        #expect(pager.count == 249)
        let shown = try await everything(in: pager)

        #expect(shown.count == 249)
        #expect(Set(shown) == Set(movies.all).subtracting([deleted]))
        #expect(pager.count == 249)
        #expect(shown[98] == lastOnFirstPage)
        #expect(shown[99] != lastOnFirstPage)
        // The order is held in the app and keeps the deleted title's place, so each later page is
        // the one it was before: none starts a place early to repeat the title before it.
        #expect(movies.pageSizesAsked == [100, 100, 50])
    }

    @Test func `a random grid leaves out a title deleted from a page it hasn't reached`() async throws {
        let movies = DeletableMovies(host: "random-delete-later.test", count: 250)
        let pager = try randomGrid(host: "random-delete-later.test")
        try await pager.start()
        let onFirstPage = Set((0 ..< 100).compactMap { pager.item(at: $0)?.id })
        let deleted = try #require(movies.all.first { !onFirstPage.contains($0) })

        // Deleted from Search, say: the grid hasn't loaded it.
        movies.delete(deleted)
        pager.remove([deleted])
        #expect(pager.count == 250)
        let shown = try await everything(in: pager)

        // Its page comes back a title short and closes up.
        #expect(shown.count == 249)
        #expect(Set(shown) == Set(movies.all).subtracting([deleted]))
        #expect(pager.count == 249)
        #expect(movies.pageSizesAsked == [100, 100, 50])
    }
}
