import AnemoneCore
import AnemoneJellyfin
#if os(tvOS) || os(iOS)
    import AVFoundation
#endif

/// How the music player plays each song: a `PlaybackController` of its own, started once the
/// song before has stopped, whose events move the player on.
extension MusicPlayer {
    /// Stops what's playing and empties the queue while a new one loads.
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
        duration = nil
        setStatus(.loading)
        return requests
    }

    func loadAll(_ source: MusicSource, shuffled: Bool, request: Int) async throws -> [MusicItem] {
        var songs: [MusicItem] = []
        var total = Self.queueLimit
        while songs.count < total {
            let page = try await loadSongs(source, shuffled, songs.count, min(Self.pageSize * 5, total - songs.count))
            guard request == requests, !page.items.isEmpty else { break }
            songs += page.items
            total = min(page.totalCount ?? total, Self.queueLimit)
            // A random order changes from one request to the next, so it comes in one page.
            if shuffled, source.isLarge {
                break
            }
        }
        return songs
    }

    func start(_ newQueue: MusicQueue) {
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
        remote?.attach(to: self)
        playCurrent()
    }

    /// Plays the queue's current entry from the start, after the song before it has stopped.
    func playCurrent() {
        guard let entry = queue.current else { return }
        plays += 1
        let play = plays
        let old = controller
        controller = nil
        failure = nil
        position = .zero
        duration = entry.song.item.runtime
        setStatus(.loading)
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
        let metadata = PlaybackMetadata(title: song.item.name, subtitle: song.artistNames)
        let request = PlaybackRequest(PlaybackQueue.Entry(itemID: song.id, metadata: metadata))
        let loadStream = loadStream
        let controller = PlaybackController(
            request: request,
            engine: makeEngine(),
            features: makeFeatures() + [SongEvents(player: self, play: play)],
        ) { _, allowsDirect, _ in
            try await loadStream(song, allowsDirect)
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
        if time != position {
            position = time
        }
        if let length = engine.duration, length != duration {
            duration = length
        }
    }

    func setStatus(_ status: Status) {
        guard status != self.status else { return }
        self.status = status
        remote?.update(from: self)
    }

    func activateAudioSession() {
        #if os(tvOS) || os(iOS)
            // Music keeps playing with the app in the background (the `audio` background mode).
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
        #endif
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
        case let .loaded(stream, _):
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
