import AnemoneCore
import AnemoneJellyfin
import Observation

/// Plays music in the background of the app, ported from Wholphin's `MusicService`: a queue of
/// songs with shuffle and repeat, which keeps playing while the user browses, until it's stopped
/// or a video starts.
///
/// Each song plays through a `PlaybackController` of its own, with an AVPlayer engine and the
/// features music needs (progress reports for now), so the server hears about each song as it
/// does about videos.
@MainActor
@Observable
public final class MusicPlayer {
    public enum Status: Equatable, Sendable {
        /// Nothing queued.
        case idle
        case loading
        case playing
        case paused
        /// Played to the end of the queue.
        case ended
        /// The song couldn't be played; `failure` says why.
        case failed
    }

    /// Fetches a page of songs: the source, whether shuffled, the first index and the limit.
    typealias SongLoader = @Sendable (MusicSource, Bool, Int, Int) async throws -> MusicPage
    /// How to fetch a song: the song, and whether the file itself may be sent.
    typealias StreamLoader = @Sendable (MusicItem, Bool) async throws -> PlaybackStream

    /// Wholphin pages a queue in as it plays; this asks for this many songs at a time.
    static let pageSize = 100
    /// The most songs a queue takes from a library, artist or genre.
    static let queueLimit = 1000
    /// Like ExoPlayer: Previous restarts the song once it has played this long.
    static let restartThreshold = Duration.seconds(3)

    /// The player playing now, which a video stops when it starts.
    public internal(set) weak static var active: MusicPlayer?

    public internal(set) var queue = MusicQueue()
    public internal(set) var status = Status.idle
    /// Why the current song couldn't play.
    public internal(set) var failure: (any Error)?
    /// How far into the song, updated a few times a second.
    public internal(set) var position = Duration.zero
    /// The song's length, once known.
    public internal(set) var duration: Duration?

    @ObservationIgnored let loadSongs: SongLoader
    @ObservationIgnored let loadStream: StreamLoader
    @ObservationIgnored let makeEngine: @MainActor () -> any PlayerEngine
    @ObservationIgnored let makeFeatures: @MainActor () -> [any PlaybackFeature]
    @ObservationIgnored let remote: (any MusicRemote)?
    @ObservationIgnored let stopTimeout: Duration
    @ObservationIgnored let tickInterval: Duration
    @ObservationIgnored var controller: PlaybackController?
    /// Counts songs started, so events from a song that was replaced are ignored.
    @ObservationIgnored var plays = 0
    /// Counts queues asked for, so a source still paging in stops when another queue starts.
    @ObservationIgnored var requests = 0
    @ObservationIgnored var ticker: Task<Void, Never>?

    /// A player for `session`'s server. `remote` shows it in Now Playing and takes the remote's
    /// commands.
    public convenience init(session: JellyfinSession, remote: (any MusicRemote)? = nil) {
        self.init(
            remote: remote,
            makeEngine: { AVPlayerEngine() },
            makeFeatures: { [ProgressReporting(session: session)] },
            loadSongs: { source, shuffled, startIndex, limit in
                try await session.songs(from: source, shuffled: shuffled, startIndex: startIndex, limit: limit)
            },
            loadStream: { song, allowsDirect in
                let prefersAC3 = Preferences.preferAC3Surround.value()
                guard let stream = session.audioStream(
                    for: song,
                    allowsDirect: allowsDirect,
                    prefersAC3Surround: prefersAC3,
                )
                else { throw PlaybackError.nothingToPlay }
                return stream
            },
        )
    }

    init(
        remote: (any MusicRemote)? = nil,
        stopTimeout: Duration = .seconds(2),
        tickInterval: Duration = .milliseconds(250),
        makeEngine: @escaping @MainActor () -> any PlayerEngine,
        makeFeatures: @escaping @MainActor () -> [any PlaybackFeature],
        loadSongs: @escaping SongLoader,
        loadStream: @escaping StreamLoader,
    ) {
        self.remote = remote
        self.stopTimeout = stopTimeout
        self.tickInterval = tickInterval
        self.makeEngine = makeEngine
        self.makeFeatures = makeFeatures
        self.loadSongs = loadSongs
        self.loadStream = loadStream
    }

    /// The song playing, or about to.
    public var current: MusicItem? {
        queue.current?.song
    }

    /// Whether there's anything queued, for the Now Playing buttons.
    public var hasQueue: Bool {
        !queue.isEmpty
    }

    /// Playing, or about to.
    public var isPlaying: Bool {
        status == .playing || status == .loading
    }

    // MARK: Starting a queue

    /// Replaces the queue with `songs` and plays the first, or a random one when `shuffled`, as
    /// Wholphin's `setQueue` does.
    public func play(_ songs: [MusicItem], shuffled: Bool = false) {
        requests += 1
        start(MusicQueue(songs, shuffled: shuffled))
    }

    /// Replaces the queue with the songs from `source`, starting once the first page is in and
    /// adding the rest as they come, as Wholphin's `addAllToQueue` does. Shuffled, the whole
    /// queue is fetched first; a library, artist or genre comes from the server in a random
    /// order, up to `queueLimit` songs. What was playing stops at once, as Wholphin's `setQueue`
    /// empties the player first.
    public func play(_ source: MusicSource, shuffled: Bool = false) async throws {
        let request = clearForNewQueue()
        do {
            if shuffled {
                let songs = try await loadAll(source, shuffled: true, request: request)
                guard request == requests else { return }
                start(MusicQueue(songs, shuffled: true))
                return
            }
            let first = try await loadSongs(source, false, 0, Self.pageSize)
            guard request == requests else { return }
            start(MusicQueue(first.items))
            let total = min(first.totalCount ?? first.items.count, Self.queueLimit)
            var loaded = first.items.count
            while loaded < total {
                let page = try await loadSongs(source, false, loaded, Self.pageSize)
                guard request == requests, !page.items.isEmpty else { return }
                queue.append(page.items)
                loaded += page.items.count
            }
        } catch {
            // Nothing started: the player stops, so Now Playing closes and the page can say why.
            if request == requests, !hasQueue {
                stop()
            }
            throw error
        }
    }

    /// Replaces the queue with the songs `load` fetches, such as an instant mix. What was
    /// playing stops at once.
    public func play(loading load: @Sendable () async throws -> [MusicItem]) async throws {
        let request = clearForNewQueue()
        do {
            let songs = try await load()
            guard request == requests else { return }
            start(MusicQueue(songs))
        } catch {
            if request == requests {
                stop()
            }
            throw error
        }
    }

    // MARK: Changing the queue

    /// Wholphin's "Play next".
    public func playNext(_ songs: [MusicItem]) {
        guard hasQueue else {
            play(songs)
            return
        }
        queue.insertNext(songs)
    }

    /// Wholphin's "Add to queue". Starts playing when nothing was queued.
    public func addToQueue(_ songs: [MusicItem]) {
        guard hasQueue else {
            play(songs)
            return
        }
        queue.append(songs)
    }

    /// Plays the queue's entry at `index`, as selecting a song in Wholphin's queue does.
    public func playEntry(at index: Int) {
        guard queue.entries.indices.contains(index) else { return }
        queue.move(to: index)
        playCurrent()
    }

    public func moveEntry(from source: Int, to destination: Int) {
        queue.moveEntry(from: source, to: destination)
    }

    /// Removes an entry; removing the one playing plays the next.
    public func removeEntry(at index: Int) {
        guard queue.remove(at: index) else { return }
        if queue.isEmpty {
            stop()
        } else if status == .ended {
            remote?.update(from: self)
        } else {
            playCurrent()
        }
    }

    public func toggleShuffle() {
        queue.setShuffled(!queue.isShuffled)
        remote?.update(from: self)
    }

    /// Off, all, one, off, as Wholphin's repeat button cycles.
    public func cycleRepeatMode() {
        queue.repeatMode = queue.repeatMode.next
    }

    // MARK: Transport

    public func resume() {
        switch status {
        case .paused:
            controller?.engine.play()
            setStatus(.playing)
        case .ended:
            // Like starting the queue again.
            queue.move(to: 0)
            playCurrent()
        case .failed:
            playCurrent()
        case .idle, .loading, .playing:
            break
        }
    }

    public func pause() {
        guard status == .playing || status == .loading, let controller else { return }
        controller.engine.pause()
        setStatus(.paused)
    }

    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    /// The next song; nothing at the end of the queue unless repeating it all.
    public func next() {
        guard let index = queue.nextIndex(automatic: false) else { return }
        queue.move(to: index)
        playCurrent()
    }

    /// ExoPlayer's `seekToPrevious`: the song before, or the start of this one once it has played
    /// a few seconds or when it's first.
    public func previous() {
        guard position <= Self.restartThreshold, let index = queue.previousIndex else {
            seek(to: .zero)
            return
        }
        queue.move(to: index)
        playCurrent()
    }

    public func seek(to target: Duration) {
        guard let controller else { return }
        let clamped = max(.zero, duration.map { min(target, $0) } ?? target)
        position = clamped
        Task {
            _ = await controller.engine.seek(to: clamped)
            remote?.update(from: self)
        }
    }

    /// Jumps by `offset`, back when negative, as Wholphin's seek buttons do.
    public func skip(by offset: Duration) {
        seek(to: position + offset)
    }

    /// Ends playback and empties the queue, as Wholphin's Stop button does.
    public func stop() {
        requests += 1
        plays += 1
        let old = controller
        controller = nil
        ticker?.cancel()
        ticker = nil
        queue = MusicQueue()
        status = .idle
        failure = nil
        position = .zero
        duration = nil
        if Self.active === self {
            Self.active = nil
        }
        remote?.detach()
        if let old {
            Task { await old.stop() }
        }
    }
}

public extension Preferences {
    /// Wholphin's experimental "Use AC3 for surround sound audio", off by default.
    static let preferAC3Surround = Preference("preferAc3Surround", default: false)
}
