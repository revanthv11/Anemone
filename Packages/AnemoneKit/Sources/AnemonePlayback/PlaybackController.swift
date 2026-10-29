import AnemoneJellyfin
import Observation

/// Plays a queue: asks the server for each entry's stream, has the engine start it at the
/// requested position, switches to a transcode if the file won't play, and tells its features
/// what happens, so they can report progress or offer what's next. Ported from the parts of
/// Wholphin's `PlaybackViewModel` that play an item.
@MainActor
@Observable
public final class PlaybackController: Identifiable {
    public enum State {
        case loading
        case playing
        /// Finished: the player closes.
        case ended
        case failed(any Error)
    }

    /// Asks the server how to play an item, once features have prepared the request.
    typealias StreamLoader = @Sendable (StreamRequest) async throws -> PlaybackStream

    public private(set) var queue: PlaybackQueue
    public internal(set) var state = State.loading
    /// What features show in the player.
    public let accessories = PlayerAccessories()
    /// Whether the player closes when an entry plays to the end and no feature has played
    /// another, as Wholphin's does with nothing up next. Up Next turns it off while it counts
    /// down, then plays the next entry or calls `finish()`.
    public var closesAtEnd = true
    public let engine: any PlayerEngine
    /// Whether the player closed. Nothing plays after that, so features can stop what they're
    /// doing when they hear `stopped`, or in `whenStopped(_:)`.
    @ObservationIgnored public private(set) var isStopped = false
    /// Counts the entries started, from 1 for the first: another entry, or the same one started
    /// again, gets the next number, while a retry as a transcode or a reload keeps it. Features
    /// keep what they know of an entry, such as segments already skipped, by it, so a retry is
    /// told from another entry however earlier entries went.
    @ObservationIgnored public private(set) var entryNumber = 0

    public var hasEnded: Bool {
        if case .ended = state {
            true
        } else {
            false
        }
    }

    // Loading streams and following the engine, in `PlaybackController+Loading.swift` and
    // `PlaybackController+Engine.swift`, share these.
    @ObservationIgnored let features: [any PlaybackFeature]
    @ObservationIgnored let loadStream: StreamLoader
    /// How often features hear where playback is.
    @ObservationIgnored let positionInterval: Duration
    /// What's loaded in the engine.
    @ObservationIgnored var stream: PlaybackStream?
    /// What `reload()` keeps for the current entry, in `Tracks/Reloading.swift`.
    @ObservationIgnored var reloading = Reloading()
    /// Whether the loaded stream's play session is open, so features hear `stopped` once.
    @ObservationIgnored var isSessionOpen = false
    /// Counts loads, so a load that a newer one replaced is dropped.
    @ObservationIgnored var loads = 0
    /// Tasks following the loaded stream, cancelled when it's replaced or playback stops.
    @ObservationIgnored var watchers: [Task<Void, Never>] = []
    @ObservationIgnored var status = PlayerStatus.paused
    @ObservationIgnored var isUnderWay = false
    @ObservationIgnored var wasPaused = false

    /// Finds the rest of the queue once the first entry is loading; see `PlaybackRequest`.
    @ObservationIgnored private var following: PlaybackRequest.Following?
    @ObservationIgnored private var followingLoad: Task<Void, Never>?
    /// Finds what plays before the first entry; see `PlaybackRequest`.
    @ObservationIgnored private var intros: PlaybackRequest.Intros?
    /// The last session's `stopped`, which a later stop waits for.
    @ObservationIgnored private var sessionEnding: Task<Void, Never>?
    @ObservationIgnored private var hasStarted = false
    /// What features asked to do once the player closes; see `whenStopped(_:)`.
    @ObservationIgnored private var stopActions: [@MainActor () -> Void] = []

    /// A player for `request` on `session`'s server, with the features every player gets.
    public convenience init(session: JellyfinSession, request: PlaybackRequest) {
        self.init(
            request: request,
            engine: PlayerChoice.engine(for: session),
            features: Self.features(for: session),
        ) { request in
            try await session.playbackStream(for: request)
        }
    }

    init(
        request: PlaybackRequest,
        engine: any PlayerEngine,
        features: [any PlaybackFeature],
        positionInterval: Duration = .seconds(1),
        loadStream: @escaping StreamLoader,
    ) {
        var queue = request.queue
        if request.shuffles {
            queue.shuffle()
        }
        self.queue = queue
        following = request.following
        intros = request.intros
        self.engine = engine
        self.features = features
        self.positionInterval = positionInterval
        self.loadStream = loadStream
    }

    /// Asks the server for a stream and starts playing it. Only the first call does anything, so
    /// a view that runs it again doesn't open a second play session.
    public func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        // What the request's `intros` finds plays first; a failure plays the queue as it is.
        if let intros, let found = try? await intros(queue.current), !isStopped {
            queue.insertBeforeCurrent(found)
        }
        // Closed while the intros were looked up: nothing more is looked up or loaded, as a task
        // started now would outlive `stop()`, which cancels what's running when it's called.
        guard !isStopped else { return }
        loadFollowing()
        entryNumber += 1
        await load(allowsDirect: true, from: queue.current.startPosition, as: beginLoad())
    }

    /// Stops playing and ends the play session, returning once features have finished with it,
    /// so the server has heard. Call when the player closes.
    public func stop() async {
        guard !isStopped else { return }
        isStopped = true
        let position = currentPosition
        followingLoad?.cancel()
        stopWatching()
        engine.stop()
        await endSession(at: position)
        let actions = stopActions
        stopActions = []
        actions.forEach { $0() }
    }

    /// Has `action` run once the player closes, after features have heard the last `stopped`; at
    /// once if it has closed. For a feature still busy after its entry's session ended, such as
    /// Up Next counting down over the last frame: no `stopped` comes when the player closes then.
    public func whenStopped(_ action: @escaping @MainActor () -> Void) {
        guard !isStopped else { return action() }
        stopActions.append(action)
    }

    /// Plays another entry from its start position, after ending the current one's session.
    /// With `markingCurrentPlayed`, that session ends at the current entry's end rather than
    /// where it is, so the server marks it played, as when moving on from the credits
    /// (`hasReachedCredits`) with Up Next, Next or the queue row.
    public func play(entryAt index: Int, markingCurrentPlayed: Bool = false) {
        guard !isStopped, queue.entries.indices.contains(index) else { return }
        let position = markingCurrentPlayed ? engine.duration ?? currentPosition : currentPosition
        stopWatching()
        engine.pause()
        queue.currentIndex = index
        entryNumber += 1
        stream = nil
        reloading.startEntry()
        state = .loading
        let attempt = beginLoad()
        Task {
            await endSession(at: position)
            await load(allowsDirect: true, from: queue.current.startPosition, as: attempt)
        }
    }

    /// Plays `queue.next`, passing over intros; does nothing at the end of the queue. From the
    /// credits, the entry is marked played, as when Up Next moves on from them.
    public func playNext() {
        guard let index = queue.nextIndex else { return }
        play(entryAt: index, markingCurrentPlayed: hasReachedCredits)
    }

    /// Whether the entry playing is at or past its credits, where `SegmentSkipping` has them
    /// start, now. Moving on from there to another entry ends this one as played, however it's
    /// done, since only the credits are left: Jellyfin marks an entry played past 90% by
    /// default, which credits often start before.
    public var hasReachedCredits: Bool {
        guard !queue.current.isIntro, let start = feature(SegmentSkipping.self)?.creditsStart else { return false }
        return currentPosition >= start
    }

    /// Closes the player, as at the end of the queue; for features such as pass-out protection.
    /// Features hear nothing more about where playback is, and the session ends as the player
    /// closes.
    public func finish() {
        guard !isStopped else { return }
        stopWatching()
        engine.pause()
        state = .ended
    }

    /// The attached feature of a type, so features can work together, such as Up Next asking
    /// the segments feature where the credits start.
    public func feature<Feature: PlaybackFeature>(_: Feature.Type) -> Feature? {
        features.lazy.compactMap { $0 as? Feature }.first
    }

    /// Adds what the request's `following` finds to the end of the queue. A failure leaves the
    /// queue as it is, so the player closes after the entries it has.
    private func loadFollowing() {
        guard let following else { return }
        self.following = nil
        followingLoad = Task { [weak self] in
            guard let entries = try? await following(), !entries.isEmpty, !Task.isCancelled else { return }
            self?.queue.append(entries)
        }
    }

    /// Ends the loaded stream's play session, if it's open, and waits until features have heard.
    /// Runs on its own, so a stop report isn't cancelled with whatever asked for it.
    func endSession(at position: Duration) async {
        if isSessionOpen {
            isSessionOpen = false
            let previous = sessionEnding
            sessionEnding = Task {
                await previous?.value
                await publish(.stopped(position))
            }
        }
        await sessionEnding?.value
    }

    func publish(_ event: PlaybackEvent) async {
        for feature in features {
            await feature.handle(event, in: self)
        }
    }

    var currentPosition: Duration {
        reloading.pendingStart ?? engine.currentTime
    }

    var progress: PlaybackProgress {
        PlaybackProgress(position: currentPosition, isPaused: status == .paused)
    }
}
