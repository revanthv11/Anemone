import AnemoneJellyfin
import Observation

/// What Anemone's overlay shows about the entry playing, kept up to date from the controller's
/// events: whether it's paused, how the server sends it, and its chapters and trickplay
/// thumbnails. The system player needs none of it, so those are only fetched once the overlay
/// asks with `loadSeekPreviews()`, and again for each entry after that.
@MainActor
@Observable
public final class PlaybackDetails: PlaybackFeature {
    /// Asks the server for an item's chapters and trickplay, for a version.
    typealias PreviewLoader = @Sendable (MediaItem.ID, String?) async throws -> SeekPreviews

    /// Paused, or not yet under way.
    public private(set) var isPaused = true
    /// The stream loaded for the entry playing.
    public private(set) var stream: PlaybackStream?
    public private(set) var entry: PlaybackQueue.Entry?
    /// `nil` until loaded; empty when the item has neither, or the server couldn't say.
    public private(set) var previews: SeekPreviews?
    /// Counts the streams loaded and the tracks switched in the one playing, without another
    /// stream (`TrackSelection`), so a view listing the engine's tracks, such as the debug
    /// panel, reads them again after each.
    public private(set) var trackChanges = 0

    @ObservationIgnored private let loadPreviews: PreviewLoader
    @ObservationIgnored private var wantsPreviews = false
    @ObservationIgnored private var previewsTask: Task<Void, Never>?

    public convenience init(session: JellyfinSession) {
        self.init { itemID, mediaSourceID in
            try await session.seekPreviews(for: itemID, mediaSourceID: mediaSourceID)
        }
    }

    init(loadPreviews: @escaping PreviewLoader) {
        self.loadPreviews = loadPreviews
    }

    public func handle(_ event: PlaybackEvent, in _: PlaybackController) async {
        switch event {
        case let .loaded(stream, entry):
            // A retry as a transcode keeps the item and its version, and so its previews.
            let isSameVideo = self.stream?.itemID == stream.itemID
                && self.stream?.mediaSourceID == stream.mediaSourceID
            self.stream = stream
            self.entry = entry
            isPaused = true
            trackChanges += 1
            if !isSameVideo {
                previews = nil
                previewsTask?.cancel()
                previewsTask = nil
                fetchPreviewsIfWanted()
            }
        case let .reloaded(stream):
            // Another stream for the same entry and version, as for a track switch: the
            // previews stay.
            self.stream = stream
            isPaused = true
            trackChanges += 1
        case .started, .resumed:
            isPaused = false
        case let .position(progress):
            isPaused = progress.isPaused
        case .paused, .ended:
            isPaused = true
        case .failed, .stopped:
            break
        }
    }

    /// The engine switched tracks in the stream playing, as `TrackSelection` has it do.
    func tracksSwitched() {
        trackChanges += 1
    }

    /// Fetches the chapters and trickplay for what's playing, and for each entry after it.
    public func loadSeekPreviews() {
        wantsPreviews = true
        fetchPreviewsIfWanted()
    }

    private func fetchPreviewsIfWanted() {
        guard wantsPreviews, previews == nil, previewsTask == nil, let stream else { return }
        let load = loadPreviews
        previewsTask = Task { [weak self] in
            // Without them the overlay still seeks, so a failure only leaves them out.
            let previews = await (try? load(stream.itemID, stream.mediaSourceID)) ?? SeekPreviews()
            guard !Task.isCancelled, let self, self.stream?.itemID == stream.itemID else { return }
            self.previews = previews
            previewsTask = nil
        }
    }
}
