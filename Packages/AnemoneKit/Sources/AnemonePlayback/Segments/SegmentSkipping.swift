import AnemoneCore
import AnemoneJellyfin
import Observation

/// Skips intros, credits, recaps, previews and commercials the way the user chose for each kind
/// (`SkipSegmentBehavior`): plays them, offers a skip button for 10 s, or jumps past them once.
/// Ported from the segment handling in Wholphin's `PlaybackViewModel` (`listenForSegments` and
/// `updateSegment`) and its `SkipSegmentButton`.
///
/// It also says which segment is playing, whatever the setting for it, so Up Next can come up
/// when the credits start, as Wholphin's does: read `current` while handling an event (this
/// feature is listed before Up Next, so it's already up to date), or set `onChange`.
@MainActor
@Observable
public final class SegmentSkipping: PlaybackFeature {
    /// Asks the server for an item's segments.
    typealias Loader = @Sendable (MediaItem.ID) async throws -> [MediaSegment]
    /// The setting for a kind of segment, read each time, so a change applies at once.
    typealias Behavior = @MainActor (MediaSegment.Kind) -> SkipSegmentBehavior

    /// The skip button's ID among the player's actions.
    public static let skipActionID = "segments.skip"

    /// The playing entry's segments, in order. Empty until the server answers, and when it has
    /// none.
    public private(set) var segments: [MediaSegment] = []
    /// The segment playback is in, of any kind and whatever the setting for it.
    public private(set) var current: MediaSegment?
    /// The segment whose skip button is showing.
    public private(set) var offered: MediaSegment?
    /// Called when `current` changes, after `current` is set, so Up Next can follow the credits.
    @ObservationIgnored public var onChange: (@MainActor (MediaSegment?) -> Void)?

    @ObservationIgnored private let load: Loader
    @ObservationIgnored private let behavior: Behavior
    /// How long the skip button stays up, as in Wholphin.
    @ObservationIgnored private let offerDuration: Duration
    /// Wholphin's `autoSkippedSegments`: segments skipped, or whose button came and went. Until
    /// another entry plays, they aren't skipped or offered again, so seeking back into one plays
    /// it rather than jumping out again.
    @ObservationIgnored private var handled: Set<MediaSegment.ID> = []
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var offerTimeout: Task<Void, Never>?
    /// The loaded entry's `PlaybackController.entryNumber`, to tell a retry as a transcode, which
    /// keeps what was skipped, from another entry.
    @ObservationIgnored private var entryNumber: Int?
    @ObservationIgnored private weak var controller: PlaybackController?

    public convenience init(session: JellyfinSession) {
        var load: Loader = { try await session.mediaSegments(for: $0) }
        #if DEBUG
            if let fakes = MediaSegment.launchArgumentFakes {
                load = { _ in fakes }
            }
        #endif
        self.init(load: load) { kind in
            Preferences.skipBehavior(for: kind).value()
        }
    }

    init(load: @escaping Loader, offerDuration: Duration = .seconds(10), behavior: @escaping Behavior) {
        self.load = load
        self.offerDuration = offerDuration
        self.behavior = behavior
    }

    public func handle(_ event: PlaybackEvent, in controller: PlaybackController) async {
        self.controller = controller
        switch event {
        case let .loaded(_, entry):
            loaded(entry, number: controller.entryNumber)
        case let .started(progress), let .position(progress), let .paused(progress), let .resumed(progress):
            update(at: progress.position)
        case .stopped:
            enter(nil)
            withdrawOffer()
        case .ended, .failed, .reloaded:
            // A reload plays the same entry, so what was skipped stays skipped.
            break
        }
    }

    /// Where the credits start, the first outro segment's start, whatever the setting for
    /// outros: moving on from past there marks an entry played (`PlaybackController`'s
    /// `hasReachedCredits`).
    public var creditsStart: Duration? {
        segments.first { $0.kind == .outro }?.start
    }

    /// Skips the segment whose button is showing, as the button does.
    public func skipOffered() {
        guard let offered else { return }
        handled.insert(offered.id)
        withdrawOffer()
        skip(offered)
    }

    /// Wholphin starts afresh with each item, but a retry as a transcode is the same entry. Told
    /// by the entry's number, not its place and item: a later entry that failed before it loaded,
    /// then a return to this one, isn't a retry.
    private func loaded(_ entry: PlaybackQueue.Entry, number: Int) {
        let isRetry = entryNumber == number
        entryNumber = number
        guard !isRetry else { return }
        loading?.cancel()
        handled = []
        segments = []
        // Whatever the entry before was in, and its button, went with it.
        enter(nil)
        withdrawOffer()
        let load = load
        loading = Task { [weak self] in
            // Without segments, playback goes on as usual.
            let segments = await (try? load(entry.itemID)) ?? []
            guard !Task.isCancelled else { return }
            self?.segments = segments
        }
    }

    /// Like Wholphin's check every 500 ms, on each position the controller sends.
    private func update(at position: Duration) {
        let segment = segments.first { $0.contains(position) }
        let number = controller?.entryNumber
        enter(segment)
        // Up Next can move on to the next entry as the credits start (with no countdown): this
        // entry's button, or its skip, would only land on the next one as it loads. Its segment
        // and any button still up go with it, rather than lasting until the next entry's events.
        guard controller?.entryNumber == number else {
            enter(nil)
            withdrawOffer()
            return
        }
        guard let segment else {
            withdrawOffer()
            return
        }
        switch behavior(segment.kind) {
        case .ignore:
            withdrawOffer()
        case .autoSkip:
            withdrawOffer()
            if handled.insert(segment.id).inserted {
                skip(segment)
            }
        case .ask:
            // Wholphin hides the button while Up Next asks what to do, and shows it again after.
            if handled.contains(segment.id) || controller?.accessories.card != nil {
                withdrawOffer()
            } else if offered != segment {
                offer(segment)
            }
        }
    }

    private func enter(_ segment: MediaSegment?) {
        guard segment != current else { return }
        current = segment
        onChange?(segment)
    }

    private func offer(_ segment: MediaSegment) {
        guard let controller else { return }
        offered = segment
        let action = PlayerAction(
            id: Self.skipActionID,
            title: segment.kind.skipTitle,
            systemImage: "forward.end.fill",
        ) { [weak self] in
            self?.skipOffered()
        }
        controller.accessories.show(action)
        offerTimeout?.cancel()
        let duration = offerDuration
        offerTimeout = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self else { return }
            // Gone for good, as Wholphin's button is.
            handled.insert(segment.id)
            withdrawOffer()
        }
    }

    private func withdrawOffer() {
        offerTimeout?.cancel()
        offerTimeout = nil
        guard offered != nil else { return }
        offered = nil
        controller?.accessories.removeAction(Self.skipActionID)
    }

    /// Wholphin seeks just past the end. A segment that runs to the end of the video skips to
    /// its end, where playback ends.
    private func skip(_ segment: MediaSegment) {
        guard let engine = controller?.engine else { return }
        var target = segment.end + .milliseconds(1)
        if let duration = engine.duration {
            target = min(target, duration)
        }
        Task {
            _ = await engine.seek(to: target)
        }
    }
}
