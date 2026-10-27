import AnemoneCore
import AnemoneJellyfin
import AnemonePlayback
import Foundation
import Synchronization
import Testing

/// The slideshow's viewer and timing, as Wholphin's `SlideshowViewModel` moves through photos.
@MainActor
struct SlideshowTests {
    /// A slideshow of `count` photos, `p0` onwards, with clips where asked, in pages of 10.
    private func slideshow(
        count: Int = 25,
        clips: Set<Int> = [],
        delay: Duration = .milliseconds(30),
        library: FakeLibrary? = nil,
    ) -> (Slideshow, FakeLibrary) {
        let library = library ?? FakeLibrary(count: count, clips: clips)
        let pager = SlideshowPager(pageSize: 10, loader: library.load)
        return (Slideshow(pager: pager, delay: delay), library)
    }

    @Test func `the viewer opens on the photo picked, found near where it was in the grid`() async throws {
        let (slideshow, library) = slideshow()

        // The grid had albums before it, so it was further along there.
        try await slideshow.load(showing: "p13", near: 16)

        #expect(slideshow.position == 13)
        #expect(slideshow.current?.id == "p13")
        #expect(slideshow.pager.count == 25)
        // The first page, then the page the grid's place was on.
        #expect(library.startIndexes == [0, 10])
    }

    @Test func `a photo not in the slideshow opens it at the first`() async throws {
        let (slideshow, _) = slideshow()

        try await slideshow.load(showing: "elsewhere", near: 3)

        #expect(slideshow.position == 0)
    }

    @Test func `left and right stop at the first and last photos`() async throws {
        let (slideshow, _) = slideshow(count: 3)
        try await slideshow.load(showing: nil)

        #expect(!slideshow.previous())
        #expect(slideshow.next())
        #expect(slideshow.next())
        #expect(!slideshow.next())
        #expect(slideshow.position == 2)
        #expect(slideshow.previous())
        #expect(slideshow.position == 1)
    }

    @Test func `moving onto a page that isn't loaded yet loads it`() async throws {
        let (slideshow, _) = slideshow()
        try await slideshow.load(showing: "p9")

        slideshow.next()

        #expect(slideshow.position == 10)
        #expect(await eventually { slideshow.current?.id == "p10" })
    }

    @Test func `the viewer stays on a photo until it's moved`() async throws {
        let (slideshow, _) = slideshow()
        try await slideshow.load(showing: nil)

        slideshow.photoShown()
        try await Task.sleep(for: .milliseconds(100))

        #expect(slideshow.position == 0)
        #expect(!slideshow.isRunning)
    }

    @Test func `a running slideshow moves on once each photo has shown for its time`() async throws {
        let (slideshow, _) = slideshow()
        try await slideshow.load(showing: nil)

        slideshow.startSlideshow()
        #expect(await eventually { slideshow.position == 1 })
        // The next photo's time starts once it has loaded.
        try await Task.sleep(for: .milliseconds(80))
        #expect(slideshow.position == 1)

        slideshow.photoShown()

        #expect(await eventually { slideshow.position == 2 })
    }

    @Test func `after the last photo the slideshow starts again from the first`() async throws {
        let (slideshow, _) = slideshow(count: 2)
        try await slideshow.load(showing: "p1")

        slideshow.startSlideshow()

        #expect(await eventually { slideshow.position == 0 })
    }

    @Test func `showing the details holds the slideshow until they close`() async throws {
        let (slideshow, _) = slideshow()
        try await slideshow.load(showing: nil)
        slideshow.startSlideshow()

        slideshow.pause()
        try await Task.sleep(for: .milliseconds(100))
        #expect(slideshow.position == 0)
        #expect(!slideshow.isActive)

        slideshow.resume()

        #expect(await eventually { slideshow.position == 1 })
    }

    @Test func `a press counts the photo's time again`() async throws {
        let (slideshow, _) = slideshow(delay: .milliseconds(80))
        try await slideshow.load(showing: nil)
        slideshow.startSlideshow()

        try await Task.sleep(for: .milliseconds(50))
        slideshow.restartTime()
        try await Task.sleep(for: .milliseconds(50))
        #expect(slideshow.position == 0)

        #expect(await eventually { slideshow.position == 1 })
    }

    @Test func `a clip plays to its end before its time starts`() async throws {
        let (slideshow, _) = slideshow(clips: [0])
        try await slideshow.load(showing: nil)
        #expect(slideshow.current?.kind == .video)

        slideshow.startSlideshow()
        slideshow.clipStarted()
        try await Task.sleep(for: .milliseconds(100))
        #expect(slideshow.position == 0)

        slideshow.clipEnded()

        #expect(await eventually { slideshow.position == 1 })
    }

    @Test func `stopping the slideshow leaves the photo showing`() async throws {
        let (slideshow, _) = slideshow()
        try await slideshow.load(showing: nil)
        slideshow.startSlideshow()

        slideshow.stopSlideshow()
        slideshow.photoShown()
        try await Task.sleep(for: .milliseconds(100))

        #expect(slideshow.position == 0)
        #expect(!slideshow.isRunning)
    }

    @Test func `the time each photo shows comes from Settings, within Wholphin's limits`() throws {
        let defaults = try #require(UserDefaults(suiteName: "SlideshowTests.\(UUID())"))
        #expect(Slideshow.delay(in: defaults) == .seconds(5))

        Preferences.slideshowDuration.set(12500, in: defaults)
        #expect(Slideshow.delay(in: defaults) == .milliseconds(12500))

        Preferences.slideshowDuration.set(200, in: defaults)
        #expect(Slideshow.delay(in: defaults) == .seconds(5))
        #expect(!Preferences.slideshowPlayVideos.defaultValue)
    }
}

/// A server's slideshow: `count` photos named by index, with clips at the indexes given.
final class FakeLibrary: Sendable {
    let count: Int
    let clips: Set<Int>
    private let starts = Mutex<[Int]>([])

    init(count: Int, clips: Set<Int> = []) {
        self.count = count
        self.clips = clips
    }

    var startIndexes: [Int] {
        starts.withLock(\.self)
    }

    var load: SlideshowPager.Loader {
        { [self] startIndex, limit, includeTotalCount in
            starts.withLock { $0.append(startIndex) }
            let items = (startIndex ..< min(startIndex + limit, count)).map { index in
                SlideshowItem(id: "p\(index)", name: "Photo \(index)", kind: clips.contains(index) ? .video : .photo)
            }
            return SlideshowPage(items: items, totalCount: includeTotalCount ? count : nil)
        }
    }
}
