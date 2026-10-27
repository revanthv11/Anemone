import AnemoneJellyfin
import AnemonePlayback

extension BrowseModel {
    /// What a page asks for to play an item, starting at `position`, or the beginning when `nil`.
    func playback(of details: ItemDetails, from position: Duration?) -> PlaybackRequest {
        PlaybackRequest(
            PlaybackQueue.Entry(itemID: details.id, startPosition: position, metadata: details.playerMetadata),
        )
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
