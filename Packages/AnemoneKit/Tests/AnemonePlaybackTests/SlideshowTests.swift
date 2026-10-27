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
        loadTimeout: Duration = .seconds(15),
        library: FakePhotoLibrary? = nil,
    ) -> (Slideshow, FakePhotoLibrary) {
        let library = library ?? FakePhotoLibrary(count: count, clips: clips)
        let pager = SlideshowPager(pageSize: 10, loader: library.load)
        return (Slideshow(pager: pager, delay: delay, loadTimeout: loadTimeout), library)
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

    // MARK: Never stuck

    @Test func `a photo that fails shows for its time, then the slideshow passes over it`() async throws {
        let (slideshow, _) = slideshow(count: 3)
        try await slideshow.load(showing: nil)
        slideshow.startSlideshow()
        var seen = [slideshow.position]

        // Each photo loads, except the second.
        for _ in 0 ..< 5 {
            let from = slideshow.position
            #expect(await eventually { slideshow.position != from })
            seen.append(slideshow.position)
            if let current = slideshow.current, current.id == "p1" {
                slideshow.itemFailed(current.id)
            } else {
                slideshow.photoShown()
            }
        }

        // Each time round after that, it goes from the first photo straight to the third.
        #expect(seen == [0, 1, 2, 0, 2, 0])
    }

    @Test func `a photo that never loads is moved on from after the load timeout`() async throws {
        let (slideshow, _) = slideshow(loadTimeout: .milliseconds(150))
        try await slideshow.load(showing: nil)
        slideshow.startSlideshow()
        #expect(await eventually { slideshow.position == 1 })

        // No photoShown for it.
        try await Task.sleep(for: .milliseconds(60))
        #expect(slideshow.position == 1)

        #expect(await eventually { slideshow.position == 2 })
    }

    @Test func `a clip that never starts, fails, or stalls doesn't hold the slideshow`() async throws {
        let (slideshow, _) = slideshow(clips: [0, 1, 2], loadTimeout: .milliseconds(100))
        try await slideshow.load(showing: nil)

        // Never starts playing.
        slideshow.startSlideshow()
        slideshow.clipStarted()
        #expect(await eventually { slideshow.position == 1 })

        // Fails: its message shows for its time.
        slideshow.clipStarted()
        slideshow.itemFailed("p1")
        #expect(await eventually { slideshow.position == 2 })

        // Plays, then stalls before its end.
        slideshow.clipStarted()
        slideshow.clipPlaying(length: .milliseconds(50))
        try await Task.sleep(for: .milliseconds(100))
        #expect(slideshow.position == 2)
        #expect(await eventually { slideshow.position == 3 })
    }

    @Test func `when nothing loads, the slideshow still goes round`() async throws {
        let (slideshow, _) = slideshow(count: 2)
        try await slideshow.load(showing: nil)
        slideshow.startSlideshow()
        slideshow.itemFailed("p0")
        #expect(await eventually { slideshow.position == 1 })
        slideshow.itemFailed("p1")

        #expect(await eventually { slideshow.position == 0 })
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
final class FakePhotoLibrary: Sendable {
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
