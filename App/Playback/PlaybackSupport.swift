import AnemoneJellyfin
import AnemonePlayback

/// Building what pages ask the player for. Every queue is put together by `request(_:)`, so
/// what joins a queue later, such as cinema intros (Phase 5c), has one place to go.
extension BrowseModel {
    /// What a page asks for to play an item, starting at `position`, or the beginning when `nil`.
    /// An episode goes on through the episodes after it, as in Wholphin; they're found once it's
    /// playing.
    func playback(of details: ItemDetails, from position: Duration?) -> PlaybackRequest {
        var following: PlaybackRequest.Following?
        if details.item.kind == .episode, let seriesID = details.item.episode?.seriesID {
            let session = session
            let episodeID = details.id
            following = { @MainActor [self] in
                let episodes = try await session.episodes(ofSeries: seriesID, from: episodeID)
                return episodes.drop { $0.id == episodeID }.map { entry(for: $0, from: nil) }
            }
        }
        return request(PlaybackQueue(entry(for: details, from: position)), following: following)
    }

    /// Play or Shuffle on a series, season, collection or playlist, like Wholphin's
    /// `PlaylistCreator`: asks the server what to play, then hands it to `play`, or says why
    /// there's nothing through `failed`. Series Play resumes the episode next up; the rest start
    /// from the beginning.
    func playQueue(
        of container: ItemDetails,
        shuffled: Bool,
        order: (sort: LibrarySort, filter: LibraryFilter)? = nil,
        play: (PlaybackRequest) -> Void,
        failed: (ItemAlert) -> Void,
    ) async {
        // One at a time, so pressing again while the server answers doesn't open a second player.
        guard !Self.isFindingQueue else { return }
        Self.isFindingQueue = true
        defer { Self.isFindingQueue = false }
        do {
            let found = try await queueItems(of: container, shuffled: shuffled, order: order)
            let resumesFirst = container.item.kind == .series && !shuffled
            let entries = found.items.enumerated().map { index, item in
                entry(for: item, from: index == 0 && resumesFirst ? item.userState.resumePosition : nil)
            }
            guard var queue = PlaybackQueue(entries: entries) else {
                failed(.nothingToPlay(
                    found.skippedCount > 0
                        ? "Only videos play here for now, so nothing in \(container.item.name) can."
                        : "\(container.item.name) has nothing to play.",
                ))
                return
            }
            queue.skippedCount = found.skippedCount
            queue.overLimitCount = found.overLimitCount
            // Playlists are shuffled here; the server shuffles the rest.
            play(request(queue, shuffles: shuffled && container.item.kind == .playlist))
        } catch {
            if let message = problem(with: error, doing: "find what to play in \(container.item.name)") {
                failed(.failed(message))
            }
        }
    }

    /// The player for a request. Every player is built here, with the features every player gets.
    func player(for request: PlaybackRequest) -> PlaybackController {
        PlaybackController(session: session, request: request)
    }

    /// What the player says when it can't play.
    func playbackProblem(with error: any Error) -> String {
        switch error {
        case SessionError.signedOut:
            noteSignedOut()
            return "\(server.name) signed you out. Go back to sign in again."
        case PlaybackError.notAllowed:
            return "\(server.name) doesn't allow you to play this. Its admin can allow playback or transcoding "
                + "for your account."
        case PlaybackError.noCompatibleStream:
            return "\(server.name) couldn't find a way to send this that Apple TV can play."
        case PlaybackError.rateLimitExceeded:
            return "You're already playing as many streams as \(server.name) allows. Stop one, then try again."
        case PlaybackError.nothingToPlay:
            return "\(server.name) didn't send anything to play."
        case PlayerError.resumeFailed:
            return "Couldn't jump to where you left off. Restart plays from the beginning."
        case let PlayerError.streamFailed(underlying):
            let reason = underlying.map { " \($0.localizedDescription)" } ?? ""
            return "Apple TV couldn't play the stream from \(server.name).\(reason)"
        default:
            return "Couldn't start playback. Check that \(server.name) is running, then try again."
        }
    }
}

/// Putting queues together.
private extension BrowseModel {
    /// Set while Play or Shuffle asks the server what to play.
    static var isFindingQueue = false

    /// Every request starts here.
    func request(
        _ queue: PlaybackQueue,
        shuffles: Bool = false,
        following: PlaybackRequest.Following? = nil,
    ) -> PlaybackRequest {
        PlaybackRequest(queue: queue, shuffles: shuffles, following: following)
    }

    /// One entry: the item from `position`, with what the player shows about it.
    func entry(for details: ItemDetails, from position: Duration?) -> PlaybackQueue.Entry {
        var metadata = details.playerMetadata
        // For Up Next's card.
        metadata.artworkURL = imageURL(details.cardImage(for: .thumb), width: 640)
        return PlaybackQueue.Entry(itemID: details.id, startPosition: position, metadata: metadata)
    }

    func queueItems(
        of container: ItemDetails,
        shuffled: Bool,
        order: (sort: LibrarySort, filter: LibraryFilter)?,
    ) async throws -> PlayableItems {
        let session = session
        let id = container.id
        switch container.item.kind {
        case .series:
            return try await PlayableItems(items: shuffled
                ? session.shuffledEpisodes(ofSeries: id)
                : session.seriesQueue(seriesID: id))
        case .season:
            guard let seriesID = container.item.episode?.seriesID else { return PlayableItems(items: []) }
            return try await PlayableItems(items: shuffled
                ? session.shuffledEpisodes(ofSeries: seriesID, season: id)
                : session.seasonQueue(seriesID: seriesID, seasonID: id))
        case .collection:
            return try await session.collectionQueue(
                id: id,
                shuffled: shuffled,
                sort: order?.sort ?? LibrarySort(.default),
                filter: order?.filter ?? LibraryFilter(),
            )
        case .playlist:
            return try await session.playlistQueue(id: id)
        default:
            return PlayableItems(items: [])
        }
    }
}

extension ItemDetails {
    /// What the player's info panel and Now Playing show: for episodes, the series, then the
    /// episode, as Wholphin's player titles them.
    var playerMetadata: PlaybackMetadata {
        var metadata = PlaybackMetadata(title: item.displayTitle, overview: item.overview)
        if item.kind == .episode {
            metadata.subtitle = [item.episodeLabel, item.name].compactMap(\.self).joined(separator: " · ")
        }
        return metadata
    }
}
