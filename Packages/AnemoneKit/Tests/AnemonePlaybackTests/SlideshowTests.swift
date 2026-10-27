import AnemoneCore
import AnemoneJellyfin
import AnemonePlayback
import Foundation
import Synchronization
import Testing

/// The slideshow's viewer and timing, as Wholphin's `SlideshowViewModel` moves through photos.
/// Its waits end when a test says so (`ManualSleeps`), not by the clock, so a busy machine can't
/// change what happens.
@MainActor
struct SlideshowTests {
    private static let delay = Duration.seconds(5)
    private static let loadTimeout = Duration.seconds(15)

    private let sleeps = ManualSleeps()

    /// A slideshow of `count` photos, `p0` onwards, with clips where asked, in pages of 10.
    private func slideshow(
        count: Int = 25,
        clips: Set<Int> = [],
        library: FakePhotoLibrary? = nil,
    ) -> (Slideshow, FakePhotoLibrary) {
        let library = library ?? FakePhotoLibrary(count: count, clips: clips)
        let pager = SlideshowPager(pageSize: 10, loader: library.load)
        let slideshow = Slideshow(
            pager: pager,
            delay: Self.delay,
            loadTimeout: Self.loadTimeout,
            sleep: sleeps.sleep,
        )
        return (slideshow, library)
    }

    /// Starts the slideshow on a photo and waits for its time to start counting, so the next
    /// call ends a wait the slideshow has begun.
    private func start(_ slideshow: Slideshow) async {
        slideshow.startSlideshow()
        #expect(await eventually { sleeps.pending == [Self.delay] })
    }

    /// Waits for the slideshow to wait `length`, then ends that wait as if the time had passed.
    private func elapse(_ length: Duration) async {
        #expect(await eventually { sleeps.pending == [length] }, "waiting \(sleeps.pending), not \(length)")
        sleeps.elapse()
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
        slideshow.restartTime()

        // Nothing waits to move it on.
        #expect(sleeps.started == 0)
        #expect(slideshow.position == 0)
        #expect(!slideshow.isRunning)
    }

    @Test func `a running slideshow moves on once each photo has shown for its time`() async throws {
        let (slideshow, _) = slideshow()
        try await slideshow.load(showing: nil)

        slideshow.startSlideshow()
        await elapse(Self.delay)
        #expect(await eventually { slideshow.position == 1 })

        // The next photo's time starts once it has loaded; until then it waits for the load.
        #expect(await eventually { sleeps.pending == [Self.loadTimeout] })
        slideshow.photoShown()
        await elapse(Self.delay)

        #expect(await eventually { slideshow.position == 2 })
    }

    @Test func `after the last photo the slideshow starts again from the first`() async throws {
        let (slideshow, _) = slideshow(count: 2)
        try await slideshow.load(showing: "p1")

        slideshow.startSlideshow()
        await elapse(Self.delay)

        #expect(await eventually { slideshow.position == 0 })
    }

    @Test func `a slideshow of one photo shows it again for the set time, not the load timeout`() async throws {
        let (slideshow, _) = slideshow(count: 1)
        try await slideshow.load(showing: nil)
        await start(slideshow)
        slideshow.photoShown()

        // Moving on lands on the same photo, which is already on screen, so nothing reports it
        // loaded again: its time starts at once, round after round.
        for _ in 0 ..< 3 {
            await elapse(Self.delay)
        }

        #expect(await eventually { sleeps.pending == [Self.delay] })
        #expect(slideshow.position == 0)
    }

    @Test func `moving on to the photo still on screen counts its time at once`() async throws {
        let (slideshow, _) = slideshow(count: 2)
        try await slideshow.load(showing: nil)
        await start(slideshow)
        slideshow.photoShown()
        await elapse(Self.delay)
        #expect(await eventually { slideshow.position == 1 })

        // The second photo never loads, so the first stays on screen behind it.
        await elapse(Self.loadTimeout)

        #expect(await eventually { slideshow.position == 0 })
        #expect(await eventually { sleeps.pending == [Self.delay] })
    }

    @Test func `showing the details holds the slideshow until they close`() async throws {
        let (slideshow, _) = slideshow()
        try await slideshow.load(showing: nil)
        await start(slideshow)

        slideshow.pause()

        #expect(sleeps.pending.isEmpty)
        #expect(slideshow.position == 0)
        #expect(!slideshow.isActive)

        slideshow.resume()
        await elapse(Self.delay)

        #expect(await eventually { slideshow.position == 1 })
    }

    @Test func `a press counts the photo's time again`() async throws {
        let (slideshow, _) = slideshow()
        try await slideshow.load(showing: nil)
        await start(slideshow)
        #expect(sleeps.started == 1)

        slideshow.restartTime()

        // The first wait is over without moving on, and a new one has started.
        #expect(await eventually { sleeps.started == 2 && sleeps.pending == [Self.delay] })
        #expect(slideshow.position == 0)
        sleeps.elapse()
        #expect(await eventually { slideshow.position == 1 })
    }

    @Test func `a clip plays to its end before its time starts`() async throws {
        let (slideshow, _) = slideshow(clips: [0])
        try await slideshow.load(showing: nil)
        #expect(slideshow.current?.kind == .video)

        // A clip that hasn't played yet waits for the load timeout, then its length on top once
        // it plays.
        slideshow.startSlideshow()
        #expect(await eventually { sleeps.pending == [Self.loadTimeout] })
        slideshow.clipPlaying(length: .seconds(40))
        #expect(await eventually { sleeps.pending == [.seconds(40) + Self.loadTimeout] })
        #expect(slideshow.position == 0)

        slideshow.clipEnded()
        await elapse(Self.delay)

        #expect(await eventually { slideshow.position == 1 })
    }

    // MARK: Never stuck

    @Test func `a photo that fails shows for its time, then the slideshow passes over it`() async throws {
        let (slideshow, _) = slideshow(count: 3)
        try await slideshow.load(showing: nil)
        await start(slideshow)
        slideshow.photoShown()
        var seen = [slideshow.position]

        // Each photo loads, except the second, whose message shows for the set time too.
        for _ in 0 ..< 5 {
            let from = slideshow.position
            await elapse(Self.delay)
            #expect(await eventually { slideshow.position != from })
            seen.append(slideshow.position)
            #expect(await eventually { sleeps.pending == [Self.loadTimeout] })
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
        let (slideshow, _) = slideshow()
        try await slideshow.load(showing: nil)
        slideshow.startSlideshow()
        await elapse(Self.delay)
        #expect(await eventually { slideshow.position == 1 })

        // No photoShown for it.
        await elapse(Self.loadTimeout)

        #expect(await eventually { slideshow.position == 2 })
    }

    @Test func `a clip that never starts, fails, or stalls doesn't hold the slideshow`() async throws {
        let (slideshow, _) = slideshow(clips: [0, 1, 2])
        try await slideshow.load(showing: nil)

        // Never starts playing.
        slideshow.startSlideshow()
        #expect(await eventually { sleeps.pending == [Self.loadTimeout] })
        slideshow.clipStarted()
        #expect(await eventually { sleeps.started == 2 && sleeps.pending == [Self.loadTimeout] })
        await elapse(Self.loadTimeout)
        #expect(await eventually { slideshow.position == 1 })

        // Fails: its message shows for its time.
        #expect(await eventually { sleeps.pending == [Self.loadTimeout] })
        slideshow.itemFailed("p1")
        await elapse(Self.delay)
        #expect(await eventually { slideshow.position == 2 })

        // Plays, then stalls before its end: moved on from once it's that long past its length.
        #expect(await eventually { sleeps.pending == [Self.loadTimeout] })
        slideshow.clipPlaying(length: .seconds(50))
        await elapse(.seconds(50) + Self.loadTimeout)
        #expect(await eventually { slideshow.position == 3 })
    }

    @Test func `when nothing loads, the slideshow still goes round`() async throws {
        let (slideshow, _) = slideshow(count: 2)
        try await slideshow.load(showing: nil)
        await start(slideshow)
        slideshow.itemFailed("p0")
        await elapse(Self.delay)
        #expect(await eventually { slideshow.position == 1 })
        #expect(await eventually { sleeps.pending == [Self.loadTimeout] })
        slideshow.itemFailed("p1")

        await elapse(Self.delay)
        #expect(await eventually { slideshow.position == 0 })
        await elapse(Self.delay)
        #expect(await eventually { slideshow.position == 1 })
    }

    @Test func `stopping the slideshow leaves the photo showing`() async throws {
        let (slideshow, _) = slideshow()
        try await slideshow.load(showing: nil)
        await start(slideshow)

        slideshow.stopSlideshow()
        slideshow.photoShown()

        #expect(sleeps.pending.isEmpty)
        #expect(sleeps.started == 1)
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

    @Test func `the time given as a launch argument is used too`() throws {
        let defaults = try #require(UserDefaults(suiteName: "SlideshowTests.\(UUID())"))

        // `-slideshowDuration 2000` puts the string "2000" in the argument domain.
        defaults.set("2000", forKey: Preferences.slideshowDuration.key)

        #expect(Slideshow.delay(in: defaults) == .seconds(2))
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
