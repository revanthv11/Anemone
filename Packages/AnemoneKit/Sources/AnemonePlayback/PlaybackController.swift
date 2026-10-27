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

    /// Asks the server how to play an item: the item, whether direct play and direct stream are
    /// allowed (not for Wholphin's retry as a transcode), and the version, which a retry keeps.
    typealias StreamLoader = @Sendable (MediaItem.ID, Bool, String?) async throws -> PlaybackStream

    public private(set) var queue: PlaybackQueue
    public private(set) var state = State.loading
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

    public var hasEnded: Bool {
        if case .ended = state {
            true
        } else {
            false
        }
    }

    @ObservationIgnored private let features: [any PlaybackFeature]
    @ObservationIgnored private let loadStream: StreamLoader
    /// Finds the rest of the queue once the first entry is loading; see `PlaybackRequest`.
    @ObservationIgnored private var following: PlaybackRequest.Following?
    @ObservationIgnored private var followingLoad: Task<Void, Never>?
    /// Finds what plays before the first entry; see `PlaybackRequest`.
    @ObservationIgnored private var intros: PlaybackRequest.Intros?
    /// How often features hear where playback is.
    @ObservationIgnored private let positionInterval: Duration
    /// What's loaded in the engine.
    @ObservationIgnored private var stream: PlaybackStream?
    /// Whether the loaded stream's play session is open, so features hear `stopped` once.
    @ObservationIgnored private var isSessionOpen = false
    /// The last session's `stopped`, which a later stop waits for.
    @ObservationIgnored private var sessionEnding: Task<Void, Never>?
    /// Counts loads, so a load that a newer one replaced is dropped.
    @ObservationIgnored private var loads = 0
    /// Tasks following the loaded stream, cancelled when it's replaced or playback stops.
    @ObservationIgnored private var watchers: [Task<Void, Never>] = []
    @ObservationIgnored private var status = PlayerStatus.paused
    @ObservationIgnored private var isUnderWay = false
    @ObservationIgnored private var wasPaused = false
    @ObservationIgnored private var hasStarted = false
    /// What features asked to do once the player closes; see `whenStopped(_:)`.
    @ObservationIgnored private var stopActions: [@MainActor () -> Void] = []

    /// A player for `request` on `session`'s server, with the features every player gets.
    public convenience init(session: JellyfinSession, request: PlaybackRequest) {
        let engine = PlayerChoice.engine(for: session)
        let profiles = DeviceProfileSource(engine)
        self.init(
            request: request,
            engine: engine,
            features: Self.features(for: session),
        ) { itemID, allowsDirect, mediaSourceID in
            let maxBitrate = AVPlayerProfile.maxBitrate
            let profile = await profiles.current
            // A retry keeps the version playing.
            if let mediaSourceID {
                return try await session.playbackStream(
                    for: itemID,
                    profile: profile,
                    maxBitrate: maxBitrate,
                    allowsDirect: allowsDirect,
                    mediaSourceID: mediaSourceID,
                )
            }
            // Otherwise the version picked on the item's page, while the server still has it.
            return try await session.playbackStream(
                forPickedVersionOf: itemID,
                profile: profile,
                maxBitrate: maxBitrate,
                allowsDirect: allowsDirect,
            )
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
        loadFollowing()
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
    /// where it is, so the server marks it played, as when Up Next moves on during the credits.
    public func play(entryAt index: Int, markingCurrentPlayed: Bool = false) {
        guard !isStopped, queue.entries.indices.contains(index) else { return }
        let position = markingCurrentPlayed ? engine.duration ?? currentPosition : currentPosition
        stopWatching()
        engine.pause()
        queue.currentIndex = index
        stream = nil
        state = .loading
        let attempt = beginLoad()
        Task {
            await endSession(at: position)
            await load(allowsDirect: true, from: queue.current.startPosition, as: attempt)
        }
    }

    /// Plays `queue.next`, passing over intros; does nothing at the end of the queue.
    public func playNext() {
        guard let index = queue.nextIndex else { return }
        play(entryAt: index)
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

    private func beginLoad() -> Int {
        loads += 1
        return loads
    }

    private func load(allowsDirect: Bool, from position: Duration?, as attempt: Int) async {
        guard !isStopped else { return }
        let entry = queue.current
        // A new entry may need the other engine, as with "Prefer MPV"; a retry keeps it.
        if stream == nil, let engine = engine as? any PerEntryEngine {
            await engine.prepare(for: entry)
            guard !isStopped, attempt == loads else { return }
        }
        do {
            let stream = try await loadStream(entry.itemID, allowsDirect, stream?.mediaSourceID)
            guard !isStopped, attempt == loads else {
                // Features never hear of a stream nothing plays, so a live stream it opened is closed here.
                await feature(LiveStreamClosing.self)?.discard(stream)
                return
            }
            await play(stream, entry, from: position)
        } catch {
            guard !isStopped, attempt == loads else { return }
            // An intro the server won't offer is passed over (Phase 5c).
            if let afterIntro = queue.afterIntroIndex {
                return play(entryAt: afterIntro)
            }
            state = .failed(error)
            await publish(.failed(error))
        }
    }

    private func play(_ stream: PlaybackStream, _ entry: PlaybackQueue.Entry, from position: Duration?) async {
        self.stream = stream
        status = .paused
        isUnderWay = false
        wasPaused = false
        let events = engine.load(stream.url, from: position, metadata: entry.metadata)
        isSessionOpen = true
        await publish(.loaded(stream, entry))
        follow(events)
    }

    /// Wholphin's `onPlayerError`: a file that won't direct play or direct stream gets another
    /// try as a transcode, from where it stopped. A transcode that fails is an error.
    private func failed(_ error: any Error) async {
        guard !isStopped, let stream else { return }
        stopWatching()
        let attempt = loads
        await publish(.failed(error))
        // Unless a feature moved on meanwhile.
        guard !isStopped, attempt == loads else { return }
        guard stream.method != .transcode else {
            if let afterIntro = queue.afterIntroIndex {
                play(entryAt: afterIntro)
            } else {
                state = .failed(error)
            }
            return
        }
        let position = currentPosition
        // Nothing plays until the transcode is ready and at the position, as when an entry loads.
        engine.pause()
        state = .loading
        let retry = beginLoad()
        // The failed session ends before the transcode's starts.
        await endSession(at: position)
        await load(allowsDirect: false, from: position > .zero ? position : queue.current.startPosition, as: retry)
    }

    private func finished() async {
        guard !isStopped else { return }
        // An intro plays straight into what follows, as in Wholphin: features don't hear it end,
        // so Up Next doesn't offer what's next.
        if let afterIntro = queue.afterIntroIndex {
            return play(entryAt: afterIntro)
        }
        stopWatching()
        let attempt = loads
        await publish(.ended)
        // A feature played another entry, as Up Next does.
        guard !isStopped, attempt == loads else { return }
        if closesAtEnd {
            state = .ended
        }
        if let duration = engine.duration {
            await endSession(at: duration)
        }
    }

    /// Ends the loaded stream's play session, if it's open, and waits until features have heard.
    /// Runs on its own, so a stop report isn't cancelled with whatever asked for it.
    private func endSession(at position: Duration) async {
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

    private func publish(_ event: PlaybackEvent) async {
        for feature in features {
            await feature.handle(event, in: self)
        }
    }

    private var currentPosition: Duration {
        engine.currentTime
    }

    private var progress: PlaybackProgress {
        PlaybackProgress(position: currentPosition, isPaused: status == .paused)
    }

    private func stopWatching() {
        watchers.forEach { $0.cancel() }
        watchers = []
    }
}

/// Following the engine.
private extension PlaybackController {
    func follow(_ events: AsyncStream<PlayerEvent>) {
        stopWatching()
        watchers = [
            Task { [weak self] in
                for await event in events {
                    // Cancelled, it still gets what the replaced stream buffered, such as its pause.
                    guard let self, !Task.isCancelled else { return }
                    switch event {
                    case .ready:
                        ready()
                        // An engine already playing when the stream loaded doesn't report it again.
                        if status == .playing {
                            await changed(to: .playing)
                        }
                    case let .status(status):
                        await changed(to: status)
                    case .ended:
                        // On their own, so the watchers they stop don't cancel what features do.
                        Task { await finished() }
                        return
                    case let .failed(error):
                        Task { await failed(error) }
                        return
                    }
                }
            },
        ]
    }

    func ready() {
        guard !isStopped else { return }
        state = .playing
        engine.play()
    }

    /// Like Wholphin: playback counts as started once it's under way, and after that, pausing
    /// and resuming are worth telling features about. Not before the stream is ready: until then
    /// it may still be on its way to the start position.
    func changed(to status: PlayerStatus) async {
        self.status = status
        guard isUnderWay else {
            guard status == .playing, case .playing = state else { return }
            isUnderWay = true
            await publish(.started(progress))
            // Unless the stream was replaced meanwhile.
            guard !Task.isCancelled else { return }
            watchers.append(Task { [weak self] in
                await self?.tellPosition()
            })
            return
        }
        guard status != .waiting else { return }
        let isPaused = status == .paused
        if isPaused != wasPaused {
            wasPaused = isPaused
            await publish(isPaused ? .paused(progress) : .resumed(progress))
        }
    }

    func tellPosition() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: positionInterval)
            guard !Task.isCancelled else { return }
            await publish(.position(progress))
        }
    }
}
