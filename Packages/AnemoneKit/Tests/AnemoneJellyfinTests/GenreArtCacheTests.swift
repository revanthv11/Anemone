import AnemoneJellyfin
import Foundation
import Testing

/// The genre art a Genres tab keeps, and what it does when the artwork can't be loaded.
@MainActor
struct GenreArtCacheTests {
    @Test func `only a revoked token signs out over genre art; other failures leave the cards plain`() async throws {
        let cache = GenreArtCache()

        let failed = try await cache.images(key: "k") { throw URLError(.timedOut) }
        let cancelled = try await cache.images(key: "k") { throw CancellationError() }
        let unexpected = try await cache.images(key: "k") { throw SessionError.unexpectedResponse }

        #expect(failed.isEmpty)
        #expect(cancelled.isEmpty)
        #expect(unexpected.isEmpty)
        await #expect(throws: GenreArtCache.Failure.signedOut) {
            try await cache.images(key: "k") { throw SessionError.signedOut }
        }
    }

    @Test func `genre art throws its own typed failure, which a page's catch covers case by case`() async {
        let cache = GenreArtCache()
        var caught: [GenreArtCache.Failure] = []

        // As the Genres tab catches it: the error is typed, so the switch must name every case,
        // and a new one fails to compile here and on the page instead of being swallowed.
        do throws(GenreArtCache.Failure) {
            _ = try await cache.images(key: "k") { throw SessionError.signedOut }
        } catch {
            switch error {
            case .signedOut:
                caught.append(error)
            }
        }

        #expect(caught == [.signedOut])
    }

    @Test func `a full set of genre art is kept for two hours, a partial one not at all`() async throws {
        var now = Date(timeIntervalSince1970: 0)
        let cache = GenreArtCache { now }
        let art = ["g1": ItemImage(itemID: "m1", kind: .backdrop, tag: "b1")]
        let other = ["g1": ItemImage(itemID: "m2", kind: .backdrop, tag: "b2")]

        // A partial set is shown but not kept.
        #expect(try await cache.images(key: "k") { GenreBackdrops(images: other, isComplete: false) } == other)
        #expect(try await cache.images(key: "k") { GenreBackdrops(images: art, isComplete: true) } == art)
        now += 2 * 60 * 60 - 1
        #expect(try await cache.images(key: "k") { GenreBackdrops(images: other, isComplete: true) } == art)
        now += 1
        #expect(try await cache.images(key: "k") { GenreBackdrops(images: other, isComplete: true) } == other)
    }
}
