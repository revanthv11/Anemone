import AnemoneCore
import AnemoneJellyfin
#if os(tvOS) || os(iOS)
    import AVFoundation
#endif

/// How the music player plays each song: a `PlaybackController` of its own, started once the
/// song before has stopped, whose events move the player on.
extension MusicPlayer {
    /// Stops what's playing and empties the queue while a new one loads. Now Playing shows
    /// Pause meanwhile, and a pause doesn't move `requests`: so a load that finds the player
    /// paused was paused by the user, and its queue starts paused.
    func clearForNewQueue() -> Int {
        requests += 1
        plays += 1
        if let old = controller {
            controller = nil
            Task { await old.stop() }
        }
        ticker?.cancel()
        queue = MusicQueue()
        failure = nil
        position = .zero
        seeksUnderWay = []
        duration = nil
        setStatus(.loading)
        return requests
    }

    /// Pages go by the server's count (`serverCount`), which takes in a playlist's entries that
    /// aren't songs, so no page starts among the songs of the one before.
    func loadAll(_ source: MusicSource, shuffled: Bool, request: Int) async throws -> [MusicItem] {
        var songs: [MusicItem] = []
        var fetched = 0
        var total = Self.queueLimit
        while fetched < total {
            let page = try await loadSongs(source, shuffled, fetched, min(Self.pageSize * 5, total - fetched))
            guard request == requests, page.serverCount > 0 else { break }
            songs += page.items
            fetched += page.serverCount
            total = min(page.totalCount ?? total, Self.queueLimit)
            // A random order changes from one request to the next, so it comes in one page.
            if source.isRandomOrder || (shuffled && source.isLarge) {
                break
            }
        }
        return songs
    }

    /// Adds the rest of `source` to the playing queue a page at a time, up to `queueLimit` of the
    /// server's entries. A page that fails ends the queue where it is: the music has started, so
    /// it plays on.
    func addPages(of source: MusicSource, after first: MusicPage, request: Int) async {
        let total = min(first.totalCount ?? first.serverCount, Self.queueLimit)
        var fetched = first.serverCount
        while fetched < total {
            let page: MusicPage
            do {
                page = try await loadSongs(source, false, fetched, Self.pageSize)
            } catch {
                guard request == requests else { return }
                let reason = String(describing: error)
                Self.log.error("A queue stopped at \(fetched) of \(total) entries, as a page failed: \(reason)")
                return
            }
            guard request == requests, page.serverCount > 0 else { return }
            if !page.items.isEmpty {
                queue.append(page.items)
                queueChanged()
            }
            fetched += page.serverCount
        }
    }

    /// Plays `newQueue` from its current entry; when `paused`, the first song loads and waits.
    func start(_ newQueue: MusicQueue, paused: Bool = false) {
        guard !newQueue.isEmpty else {
            stop()
            return
        }
        if let other = Self.active, other !== self {
            other.stop()
        }
        Self.active = self
        activateAudioSession()
        queue = newQueue
        playCurrent(paused: paused)
    }

    /// Plays the queue's current entry from the start, after the song before it has stopped.
    /// When `paused`, the song loads and waits, paused, as ExoPlayer moves between songs while
    /// paused.
    func playCurrent(paused: Bool = false) {
        guard let entry = queue.current else { return }
        plays += 1
        let play = plays
        let old = controller
        controller = nil
        failure = nil
        position = .zero
        // A new song starts from the top; a seek in the last one mustn't hold this one's clock.
        seeksUnderWay = []
        duration = entry.song.item.runtime
        setStatus(paused ? .paused : .loading)
        Task {
            if let old {
                await retire(old)
            }
            guard play == plays else { return }
            let controller = makeController(for: entry.song, play: play)
            self.controller = controller
            startTicking()
            await controller.start()
        }
    }

    func makeController(for song: MusicItem, play: Int) -> PlaybackController {
        let metadata = PlaybackMetadata(
            title: song.item.name,
            subtitle: song.artistNames,
            artworkURL: artworkURL(song),
        )
        let request = PlaybackRequest(PlaybackQueue.Entry(itemID: song.id, metadata: metadata))
        let loadStream = loadStream
        let engine = SongEngine(makeEngine()) { [weak self] in
            self?.status == .paused
        }
        // Now Playing before the song's events, so it shows the song before the player moves on
        // at its end.
        let shared: [any PlaybackFeature] = nowPlaying.map { [$0] } ?? []
        let controller = PlaybackController(
            request: request,
            engine: engine,
            features: makeFeatures() + shared + [SongEvents(player: self, play: play)],
        ) { request in
            try await loadStream(song, request.allowsDirect)
        }
        // The player moves on itself; nothing closes.
        controller.closesAtEnd = false
        return controller
    }

    /// Stops a song's controller and waits for the server to hear, so it hears about songs in
    /// order; but no longer than `stopTimeout`, so a slow server doesn't hold up the next song.
    func retire(_ old: PlaybackController) async {
        let timeout = stopTimeout
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumer = Resumer(continuation)
            Task {
                await old.stop()
                resumer.resume()
            }
            Task {
                try? await Task.sleep(for: timeout)
                resumer.resume()
            }
        }
    }

    /// The song's engine, which knows whether its stream is ready.
    var songEngine: SongEngine? {
        controller?.engine as? SongEngine
    }

    func startTicking() {
        ticker?.cancel()
        ticker = Task { [weak self, tickInterval] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: tickInterval)
            }
        }
    }

    func tick() {
        guard let engine = controller?.engine, status == .playing || status == .paused else { return }
        let time = engine.currentTime
        if seeksUnderWay.isEmpty, time != position {
            position = time
        }
        if let length = engine.duration, length != duration {
            duration = length
        }
    }

    func setStatus(_ status: Status) {
        guard status != self.status else { return }
        self.status = status
        updateOffer()
    }

    /// Like Wholphin's drawer: Now Playing is offered while the music plays, until two hours after
    /// it's paused or finished, and not once it's stopped.
    func updateOffer() {
        switch status {
        case .loading, .playing:
            offerExpiry?.cancel()
            offerExpiry = nil
            offersNowPlaying = true
        case .idle:
            offerExpiry?.cancel()
            offerExpiry = nil
            offersNowPlaying = false
        case .paused, .ended, .failed:
            guard offerExpiry == nil, offersNowPlaying else { return }
            offerExpiry = Task { [weak self, offerTimeout] in
                try? await Task.sleep(for: offerTimeout)
                guard !Task.isCancelled, let self else { return }
                offerExpiry = nil
                offersNowPlaying = false
            }
        }
    }

    func activateAudioSession() {
        #if os(tvOS) || os(iOS)
            // Music keeps playing with the app in the background (the `audio` background mode).
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    /// Now Playing shows the song's new place and whether there's a next at once, rather than
    /// at the song's next position event, which never comes at the end of the queue.
    func queueChanged() {
        nowPlaying?.musicQueueChanged()
    }

    // MARK: What the song's controller says

    func songStatus(_ status: Status, play: Int) {
        guard play == plays else { return }
        setStatus(status)
    }

    /// Plays what comes next, the same song when repeating one, or stops at the end.
    func songEnded(play: Int) {
        guard play == plays else { return }
        if let index = queue.nextIndex(automatic: true) {
            queue.move(to: index)
            playCurrent()
        } else {
            plays += 1
            if let old = controller {
                controller = nil
                Task { await old.stop() }
            }
            ticker?.cancel()
            position = duration ?? position
            setStatus(.ended)
        }
    }

    func songFailed(_ error: any Error, play: Int) {
        guard play == plays else { return }
        failure = error
        setStatus(.failed)
    }
}

/// Passes a song controller's events to the player.
@MainActor
private final class SongEvents: PlaybackFeature {
    private weak var player: MusicPlayer?
    private let play: Int
    /// The loaded stream's method: a failed transcode is final, anything else is tried again
    /// as a transcode.
    private var method: PlaybackMethod?

    init(player: MusicPlayer, play: Int) {
        self.player = player
        self.play = play
    }

    func handle(_ event: PlaybackEvent, in _: PlaybackController) async {
        guard let player else { return }
        switch event {
        case let .loaded(stream, _), let .reloaded(stream):
            method = stream.method
        case .started, .resumed:
            player.songStatus(.playing, play: play)
        case .paused:
            player.songStatus(.paused, play: play)
        case .ended:
            player.songEnded(play: play)
        case let .failed(error):
            if method == nil || method == .transcode {
                player.songFailed(error, play: play)
            }
        case .position, .stopped:
            break
        }
    }
}

/// Resumes a continuation once, whichever task gets there first.
@MainActor
private final class Resumer {
    private var continuation: CheckedContinuation<Void, Never>?

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
