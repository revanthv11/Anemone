import AnemoneJellyfin
import Foundation

/// Up Next and pass-out protection, ported from Wholphin's `PlaybackViewModel` and
/// `PlaybackPage`. When an entry with another after it ends, a card offers the next one and
/// counts down to playing it; Cancel closes the player. With "During the credits", the card comes
/// when `SegmentSkipping` finds the outro instead, once for each outro and in place of its skip
/// button, as in Wholphin; Cancel keeps the credits playing until the card comes back at the end.
/// Going back before the credits takes the card down until they play again. Moving on from the
/// credits marks the entry played, which Wholphin doesn't (see `play(_:)`).
///
/// Pass-out protection: once `passOutCount` entries have played on their own with no press on
/// the remote, the card asks "Still watching?" instead, and playback stops when nobody answers.
/// Wholphin stops counting down after two hours without a press; this counts entries.
///
/// It also says so when the queue was built without items that can't play here, or that didn't
/// fit in it.
@MainActor
public final class UpNext: PlaybackFeature {
    /// The cards it shows, by ID.
    public static let upNextCard = "upNext"
    public static let stillWatchingCard = "stillWatching"
    public static let skippedCard = "skipped"
    /// Stands in for an outro segment's ID where the `-upNextCreditsAt` launch argument says the
    /// credits start.
    static let testCreditsID = "upNextCreditsAt"

    private let settings: Settings
    /// How long one second of a countdown takes; shorter in tests.
    let second: Duration
    /// Entries that played on their own since the last press on the remote.
    private(set) var autoplaysWithoutInput = 0
    private weak var controller: PlaybackController?
    /// What's on offer while a card for it shows.
    private var offer: Offer?
    /// Counts down the card on offer.
    private var countdown: Task<Void, Never>?
    /// Wholphin's `outroShownSegments`: the credits in the entry playing that Up Next has come up
    /// at, by segment ID, so it does once for each. A retry as a transcode keeps them, so a card
    /// the user cancelled doesn't come back.
    private var creditsOffered: Set<MediaSegment.ID> = []
    /// The loaded entry's `PlaybackController.entryNumber`, to tell a retry as a transcode from
    /// another entry, as segment skipping does.
    private var entryNumber: Int?
    var noteTimer: Task<Void, Never>?
    var hasNotedSkipped = false

    private struct Offer {
        /// At the end of the entry rather than during its credits, so Cancel closes the player.
        var isAtEnd: Bool
        /// The credits it came up at, if it did.
        var creditsID: MediaSegment.ID?
    }

    /// - Parameter second: how long one second of a countdown takes, for tests.
    public init(settings: Settings = .current(), second: Duration = .seconds(1)) {
        self.settings = settings
        self.second = second
    }

    public func handle(_ event: PlaybackEvent, in controller: PlaybackController) async {
        follow(controller)
        switch event {
        case .loaded:
            loaded(number: controller.entryNumber)
            controller.closesAtEnd = true
        case .started:
            noteSkipped(in: controller)
        case let .position(progress):
            moved(to: progress.position, in: controller)
        case .resumed:
            // Only a resume: the player pauses on its own at the end of an entry.
            noteRemoteInput()
        case .ended:
            ended(in: controller)
        case .failed:
            failed()
        case .paused, .stopped, .reloaded:
            // A reload plays the same entry: an offer, or one cancelled, carries on.
            break
        }
    }

    /// Tells Up Next the credits with this ID, an outro segment's, have started in the entry
    /// playing, as the media segments feature finds them. With "During the credits", the card
    /// shows now rather than at the end, once for each.
    public func creditsStarted(id: MediaSegment.ID) {
        // Never during an intro, which plays straight into what follows (Phase 5c).
        guard let controller, offer == nil, !controller.queue.current.isIntro, controller.queue.next != nil,
              settings.timing == .duringCredits || settings.testCreditsStart != nil,
              creditsOffered.insert(id).inserted
        else { return }
        offerNext(atEnd: false, creditsID: id, in: controller)
    }

    /// A press or touch on the remote: someone's awake, so pass-out protection counts from 0.
    public func noteRemoteInput() {
        autoplaysWithoutInput = 0
    }
}

/// Following the player.
private extension UpNext {
    /// The first time it hears from `controller`.
    func follow(_ controller: PlaybackController) {
        guard self.controller !== controller else { return }
        self.controller = controller
        // The moment the credits start, before segment skipping offers to skip them, so the card
        // comes up in place of its skip button, as in Wholphin.
        controller.feature(SegmentSkipping.self)?.onChange = { [weak self] segment in
            if let segment, segment.kind == .outro {
                self?.creditsStarted(id: segment.id)
            }
        }
        // The player can close after the entry's session ended, while the card counts down over
        // the last frame, and no `stopped` comes then.
        controller.whenStopped { [weak self] in
            self?.closed()
        }
    }

    /// Starts afresh with each entry, but a retry as a transcode is the same one. Told by the
    /// entry's number, so a later entry that failed before it loaded, then a return to this one,
    /// isn't taken for a retry.
    func loaded(number: Int) {
        withdraw()
        if entryNumber != number {
            creditsOffered = []
        }
        entryNumber = number
    }

    /// Segment skipping hears each event first, so it already knows the segment playing. Checked
    /// at each position too, for a next entry found after the credits started.
    func moved(to position: Duration, in controller: PlaybackController) {
        if hasLeftCredits(at: position) {
            creditsLeft()
        } else if let segment = controller.feature(SegmentSkipping.self)?.current, segment.kind == .outro {
            creditsStarted(id: segment.id)
        } else if let start = settings.testCreditsStart, position >= start {
            creditsStarted(id: Self.testCreditsID)
        }
    }

    /// The card goes with the stream. If a retry as a transcode follows, credits whose card was
    /// still up bring it back; ones whose card the user cancelled don't.
    func failed() {
        if let creditsID = offer?.creditsID {
            creditsOffered.remove(creditsID)
        }
        withdraw()
    }

    /// The player closed: nothing more to count down or show.
    func closed() {
        withdraw()
        noteTimer?.cancel()
    }
}

/// Offering the next entry.
private extension UpNext {
    func ended(in controller: PlaybackController) {
        guard controller.queue.next != nil else { return }
        // The player stays open with the card over the last frame.
        controller.closesAtEnd = false
        if var offer {
            // Offered during the credits and still counting: from now on, Cancel closes.
            offer.isAtEnd = true
            self.offer = offer
        } else {
            offerNext(atEnd: true, in: controller)
        }
    }

    func offerNext(atEnd: Bool, creditsID: MediaSegment.ID? = nil, in controller: PlaybackController) {
        guard let index = controller.queue.nextIndex else { return }
        let next = controller.queue.entries[index]
        // Also when it plays at once, for whether moving on marks the entry played.
        offer = Offer(isAtEnd: atEnd, creditsID: creditsID)
        if settings.autoplays, settings.passOutCount > 0, autoplaysWithoutInput >= settings.passOutCount {
            count(down: settings.stillWatchingTimeout) { [weak self] left in
                self?.showStillWatching(next, index: index, left: left)
            } then: { [weak self] in
                self?.stop()
            }
        } else if settings.autoplays, settings.countdown <= .zero {
            autoplay(index)
        } else {
            guard settings.autoplays else {
                // Wholphin still offers the next entry, without counting down.
                showUpNext(next, index: index, left: nil)
                return
            }
            count(down: settings.countdown) { [weak self] left in
                self?.showUpNext(next, index: index, left: left)
            } then: { [weak self] in
                self?.autoplay(index)
            }
        }
    }

    func showUpNext(_ next: PlaybackQueue.Entry, index: Int, left: Duration?) {
        controller?.accessories.show(PlayerCard(
            id: Self.upNextCard,
            title: "Up Next",
            message: [next.metadata.fullTitle, left.map { "Plays in \($0.wholeSeconds) s" }]
                .compactMap(\.self)
                .joined(separator: "\n"),
            imageURL: next.metadata.artworkURL,
            actions: [
                PlayerAction(id: "upNext.play", title: "Play Now", systemImage: "play.fill") { [weak self] in
                    self?.noteRemoteInput()
                    self?.play(index)
                },
                PlayerAction(id: "upNext.cancel", title: "Cancel") { [weak self] in
                    self?.noteRemoteInput()
                    self?.cancel()
                },
            ],
        ))
    }

    func showStillWatching(_ next: PlaybackQueue.Entry, index: Int, left: Duration) {
        controller?.accessories.show(PlayerCard(
            id: Self.stillWatchingCard,
            title: "Still watching?",
            message: "Next: \(next.metadata.fullTitle)\nStopping in \(left.wholeSeconds) s",
            imageURL: next.metadata.artworkURL,
            actions: [
                PlayerAction(id: "stillWatching.continue", title: "Keep Watching") { [weak self] in
                    self?.noteRemoteInput()
                    self?.play(index)
                },
                PlayerAction(id: "stillWatching.stop", title: "Stop") { [weak self] in
                    self?.noteRemoteInput()
                    self?.stop()
                },
            ],
        ))
    }

    /// Plays the entry offered, as at the end of the countdown. Not when playback went back
    /// before the credits the card came up at within the last second, before a position said so.
    func autoplay(_ index: Int) {
        if let controller, hasLeftCredits(at: controller.currentPosition) {
            return creditsLeft()
        }
        autoplaysWithoutInput += 1
        play(index)
    }

    /// Moving on from the credits marks the entry played, as at its end. Wholphin reports where
    /// it stopped instead, which leaves an entry whose credits start before the server's played
    /// threshold (90% by default) to resume, in Continue Watching.
    func play(_ index: Int) {
        guard let controller, let offer else { return }
        // At its end, or still past where the credits the card came up at start.
        let marksPlayed = offer.isAtEnd || (offer.creditsID != nil && !hasLeftCredits(at: controller.currentPosition))
        withdraw()
        controller.play(entryAt: index, markingCurrentPlayed: marksPlayed)
    }

    /// At the end, closes the player; during the credits, lets them play.
    func cancel() {
        guard let offer else { return }
        withdraw()
        if offer.isAtEnd {
            controller?.finish()
        }
    }

    func stop() {
        withdraw()
        controller?.finish()
    }

    /// Whether playback is back before the credits the card came up at, as after seeking back.
    func hasLeftCredits(at position: Duration) -> Bool {
        guard let offer, !offer.isAtEnd, let id = offer.creditsID else { return false }
        let start = id == Self.testCreditsID
            ? settings.testCreditsStart
            : controller?.feature(SegmentSkipping.self)?.segments.first { $0.id == id }?.start
        return start.map { position < $0 } ?? false
    }

    /// Playback went back before the credits the card came up at: it goes, so its countdown
    /// doesn't move on from part of the entry still to watch and end it as played. The credits
    /// bring it again when they play. Wholphin turns its controls off while its card is up.
    func creditsLeft() {
        if let id = offer?.creditsID {
            creditsOffered.remove(id)
        }
        withdraw()
    }

    /// Takes the card down and stops its countdown.
    func withdraw() {
        countdown?.cancel()
        countdown = nil
        offer = nil
        controller?.accessories.dismissCard(Self.upNextCard)
        controller?.accessories.dismissCard(Self.stillWatchingCard)
    }

    /// Calls `tick` with the time left, now and at each second after, then `done`, unless
    /// withdrawn first.
    func count(
        down length: Duration,
        tick: @escaping @MainActor (Duration) -> Void,
        then done: @escaping @MainActor () -> Void,
    ) {
        countdown?.cancel()
        tick(length)
        let second = second
        countdown = Task {
            var left = length
            while left > .zero {
                try? await Task.sleep(for: second)
                guard !Task.isCancelled else { return }
                left -= .seconds(1)
                if left > .zero {
                    tick(left)
                }
            }
            done()
        }
    }
}

extension PlaybackMetadata {
    /// The title and, for episodes, the episode: "Pioneer One · S1:E2 · The Man From Mars".
    var fullTitle: String {
        [title, subtitle].compactMap(\.self).joined(separator: " · ")
    }
}

private extension Duration {
    /// Rounded up, so a countdown never shows 0.
    var wholeSeconds: Int64 {
        let (seconds, attoseconds) = components
        return attoseconds > 0 ? seconds + 1 : seconds
    }
}
