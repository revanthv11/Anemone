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
    /// The video of a version of an item, from the server.
    typealias VideoLoader = @Sendable (MediaItem.ID, String?) async throws -> MediaVersion.Video?
    /// Asks the display for a mode; `nil` for its usual one.
    typealias Apply = @MainActor (DisplayCriteria?) -> Void

    /// Whether AVKit's system player shows the video, and so matches the display itself; when
    /// `nil`, as `PlayerScreen` chooses (`showsInSystemPlayer`).
    public var usesSystemPlayer: Bool?
    /// What the display was asked for; `nil` when it's left alone.
    public private(set) var applied: DisplayCriteria?

    private let loadVideo: VideoLoader
    private let apply: Apply
    private let decoders: VideoDecoders
    /// How long to wait after a play session ends before going back to the usual mode, so the
    /// next entry in a queue doesn't make the display switch twice.
    private let resetDelay: Duration
    private var loading: Task<Void, Never>?
    private var pendingReset: Task<Void, Never>?

    private static let log = Logger(subsystem: "com.revanthv11.anemone", category: "Playback")

    public convenience init(session: JellyfinSession) {
        self.init(
            loadVideo: { itemID, versionID in
                let versions = try await session.mediaVersions(of: itemID)
                return (versions.first { $0.id == versionID } ?? versions.first)?.video
            },
            apply: Self.applyToDisplay,
        )
    }

    init(
        loadVideo: @escaping VideoLoader,
        apply: @escaping Apply,
        decoders: VideoDecoders = .current,
        resetDelay: Duration = .seconds(2),
    ) {
        self.loadVideo = loadVideo
        self.apply = apply
        self.decoders = decoders
        self.resetDelay = resetDelay
    }

    public func handle(_ event: PlaybackEvent, in controller: PlaybackController) async {
        switch event {
        case let .loaded(stream, entry):
            pendingReset?.cancel()
            pendingReset = nil
            guard !(usesSystemPlayer ?? controller.engine.showsInSystemPlayer) else {
                change(to: nil)
                return
            }
            match(entry.itemID, stream)
        case .stopped:
            loading?.cancel()
            loading = nil
            scheduleReset()
        case .started, .position, .paused, .resumed, .ended, .failed:
            break
        }
    }

    private func match(_ itemID: MediaItem.ID, _ stream: PlaybackStream) {
        loading?.cancel()
        let load = loadVideo
        let decoders = decoders
        loading = Task { [weak self] in
            // Without the video's details, the display goes back to its usual mode.
            let video = try? await load(itemID, stream.mediaSourceID)
            guard !Task.isCancelled, let self else { return }
            change(to: video.flatMap { DisplayCriteria(video: $0, method: stream.method, decoders: decoders) })
        }
    }

    /// Only when it's a change, so the next entry of a series doesn't blank the screen again.
    private func change(to criteria: DisplayCriteria?) {
        guard criteria != applied else { return }
        applied = criteria
        if let criteria {
            let range = String(describing: criteria.dynamicRange)
            Self.log.notice("Display criteria: \(criteria.frameRate, privacy: .public) fps, \(range, privacy: .public)")
        }
        apply(criteria)
    }

    /// Holds what it needs rather than the feature, which goes when the player closes.
    private func scheduleReset() {
        guard applied != nil else { return }
        let apply = apply
        let delay = resetDelay
        pendingReset = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.applied = nil
            apply(nil)
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

private extension DisplayCriteriaMatching {
    static func applyToDisplay(_ criteria: DisplayCriteria?) {
        #if os(tvOS)
            guard let manager = keyWindow?.avDisplayManager else { return }
            guard let criteria else {
                manager.preferredDisplayCriteria = nil
                return
            }
            // tvOS ignores the request when Match Content is off.
            guard manager.isDisplayCriteriaMatchingEnabled, let format = criteria.formatDescription() else { return }
            manager.preferredDisplayCriteria = AVDisplayCriteria(
                refreshRate: criteria.frameRate,
                formatDescription: format,
            )
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
