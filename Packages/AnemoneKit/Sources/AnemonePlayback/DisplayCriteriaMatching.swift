import AnemoneJellyfin
import Foundation
import os
#if os(tvOS)
    import AVFoundation
    import AVKit
    import UIKit
#endif

/// Asks the display for the playing video's frame rate and dynamic range (`DisplayCriteria`),
/// and back to its usual mode when the player closes, as Wholphin's `RefreshRateService` does
/// with `changeRefreshRate` and `resetRefreshRate`. tvOS only switches when the user turned on
/// Match Content.
///
/// AVKit's system player does this itself (`appliesPreferredDisplayCriteriaAutomatically`), so
/// this is for Anemone's overlay and MPV (Phase 4), which have nothing doing it for them.
@MainActor
public final class DisplayCriteriaMatching: PlaybackFeature {
    /// Whether AVKit's system player shows the video, and so matches the display itself; when
    /// `nil`, as `PlayerScreen` chooses (`showsInSystemPlayer`).
    public var usesSystemPlayer: Bool?

    private let display: Display
    private let decoders: VideoDecoders
    /// How long to wait after the player closes before going back to the usual mode, so a
    /// player opened straight after doesn't make the display switch twice.
    private let resetDelay: Duration
    /// Whether the display goes back to its usual mode once this player closes.
    private var resetsWhenClosed = false

    public convenience init() {
        self.init(display: .shared)
    }

    init(display: Display, decoders: VideoDecoders = .current, resetDelay: Duration = .seconds(2)) {
        self.display = display
        self.decoders = decoders
        self.resetDelay = resetDelay
    }

    public func handle(_ event: PlaybackEvent, in controller: PlaybackController) async {
        switch event {
        case let .loaded(stream, _), let .reloaded(stream):
            // PlaybackInfo described the video, so there's nothing more to ask the server.
            let criteria = (usesSystemPlayer ?? controller.engine.showsInSystemPlayer)
                ? nil
                : DisplayCriteria(stream: stream, decoders: decoders)
            display.request(criteria, by: self)
            resetWhenClosed(controller)
        case .stopped:
            // An entry's session ends before the next entry's PlaybackInfo is asked for, which
            // can take a while (a slow server, or a picked version gone from it), and an entry
            // that ended may wait for Up Next. So the display keeps its mode until the player
            // closes, rather than switching back and forth between entries.
            break
        case .started, .position, .paused, .resumed, .ended, .failed:
            break
        }
    }

    /// Once, when the player first asks for a mode.
    private func resetWhenClosed(_ controller: PlaybackController) {
        guard !resetsWhenClosed else { return }
        resetsWhenClosed = true
        controller.whenStopped { [weak self] in
            guard let self else { return }
            display.reset(after: resetDelay, by: self)
        }
    }
}

extension DisplayCriteriaMatching {
    /// Waits as `Task.sleep` does; tests end the waits themselves, so they don't depend on how
    /// busy the machine is.
    typealias Sleep = @Sendable (Duration) async throws -> Void

    /// The display, which every player's feature asks through one shared instance. A player
    /// leaves a reset behind as it closes, and the reset belongs to that player's feature: the
    /// next player to ask for a mode cancels it, and a feature that's no longer the last to ask
    /// can't reset the display, so a reset never undoes what another player asked for.
    @MainActor
    final class Display {
        static let shared = Display(apply: DisplayCriteriaMatching.applyToDisplay)

        /// What the display was last set to; `nil` while it's in its usual mode.
        private(set) var criteria: DisplayCriteria?
        /// Asks the display for a mode, `nil` for its usual one, and says whether it was asked:
        /// there may be no window yet, and tvOS ignores the request while Match Content is off.
        private let apply: @MainActor (DisplayCriteria?) -> Bool
        private let sleep: Sleep
        /// The feature that asked last, the only one that may reset the display.
        private weak var owner: DisplayCriteriaMatching?
        private var pendingReset: Task<Void, Never>?

        private static let log = Logger(subsystem: "com.revanthv11.anemone", category: "Playback")

        init(
            apply: @escaping @MainActor (DisplayCriteria?) -> Bool,
            sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
        ) {
            self.apply = apply
            self.sleep = sleep
        }

        /// Whether a closed player's reset is waiting to go back to the usual mode.
        var isResetPending: Bool {
            pendingReset != nil
        }

        /// The mode for `feature`'s video; `nil` for the usual one.
        func request(_ criteria: DisplayCriteria?, by feature: DisplayCriteriaMatching) {
            pendingReset?.cancel()
            pendingReset = nil
            owner = feature
            change(to: criteria)
        }

        /// Back to the usual mode after `delay`, unless another player asks for a mode first.
        func reset(after delay: Duration, by feature: DisplayCriteriaMatching) {
            guard owner === feature, criteria != nil else { return }
            pendingReset?.cancel()
            let sleep = sleep
            pendingReset = Task { [weak self] in
                try? await sleep(delay)
                guard !Task.isCancelled, let self else { return }
                pendingReset = nil
                owner = nil
                change(to: nil)
            }
        }

        /// Only when it's a change, so the next entry of a series doesn't blank the screen again.
        /// What the display wasn't asked for isn't kept, so the same mode asked for again, by
        /// the next entry once there's a window, still reaches it.
        private func change(to criteria: DisplayCriteria?) {
            guard criteria != self.criteria, apply(criteria) else { return }
            self.criteria = criteria
            if let criteria {
                let summary = "\(criteria.frameRate) fps, \(criteria.dynamicRange), \(criteria.codecName)"
                Self.log.notice("Display criteria: \(summary, privacy: .public)")
            }
        }
    }
}

public extension DisplayCriteriaMatching {
    /// Whether this Apple TV switches modes for content, from Match Content; `nil` where there's
    /// no such setting.
    static var isMatchingEnabled: Bool? {
        #if os(tvOS)
            keyWindow?.avDisplayManager.isDisplayCriteriaMatchingEnabled
        #else
            nil
        #endif
    }
}

private extension DisplayCriteria {
    /// The codec's four characters, such as `hvc1`, for the log.
    var codecName: String {
        String(bytes: withUnsafeBytes(of: codec.bigEndian, Array.init), encoding: .ascii) ?? "\(codec)"
    }
}

private extension DisplayCriteriaMatching {
    /// Whether the display was asked: not without a window, nor for a mode while Match Content
    /// is off, since tvOS would ignore it.
    static func applyToDisplay(_ criteria: DisplayCriteria?) -> Bool {
        #if os(tvOS)
            guard let manager = keyWindow?.avDisplayManager else { return false }
            guard let criteria else {
                manager.preferredDisplayCriteria = nil
                return true
            }
            guard manager.isDisplayCriteriaMatchingEnabled, let format = criteria.formatDescription() else {
                return false
            }
            manager.preferredDisplayCriteria = AVDisplayCriteria(
                refreshRate: criteria.frameRate,
                formatDescription: format,
            )
            return true
        #else
            false
        #endif
    }

    #if os(tvOS)
        static var keyWindow: UIWindow? {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)
        }
    #endif
}
