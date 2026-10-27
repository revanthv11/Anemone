/// What `PlaybackController.reload()` keeps track of for the entry playing.
struct Reloading {
    /// Whether the last load allowed direct play, which a reload keeps.
    var allowsDirect = true
    /// Whether the entry's stream was replaced with `reload()`. Features then hear `reloaded` for
    /// its later streams too, a transcode retry's included, since it's still the same entry.
    var hasReloaded = false
    /// Where the loaded stream starts, until the engine is ready there: the engine's time says 0
    /// until then, and a reload before that plays on from here.
    var pendingStart: Duration?
    /// Whether the loaded stream stays paused once it's ready, as after a reload while paused.
    var staysPaused = false
    /// Whether the server is being asked for a stream.
    var isAsking = false
    /// Whether a reload came while the server was asked. Once the request has gone out, its
    /// answer is dropped and the server asked again, for what's chosen by then, so quick picks
    /// in the Audio and Subtitles menus come to one more request rather than one each.
    var asksAgain = false

    /// Another entry: its streams are `loaded` until it's reloaded, and it plays once it's ready.
    mutating func startEntry() {
        hasReloaded = false
        staysPaused = false
    }

    /// A request for a stream is about to be prepared, so picks from now on are in it.
    mutating func asks(allowsDirect: Bool) {
        self.allowsDirect = allowsDirect
        asksAgain = false
    }

    /// The server answered with a stream that's loading, to start at `position`, which is where
    /// playback is until the engine is ready there.
    mutating func answered(startingAt position: Duration) {
        isAsking = false
        pendingStart = position
    }

    /// Whether a reload starts now. While the server is asked for a stream it doesn't: the
    /// request asks for what's chosen by the time it goes out, or is asked again afterwards.
    mutating func starts() -> Bool {
        guard !isAsking else {
            asksAgain = true
            return false
        }
        hasReloaded = true
        return true
    }
}

public extension PlaybackController {
    /// Asks the server for the current entry again, after ending its play session, and plays
    /// the new stream on from where the old one was: for audio or subtitles the stream doesn't
    /// carry, as Wholphin's `changeStreams` does. Features hear `reloaded` rather than `loaded`,
    /// since the entry is the same. Paused, it stays paused until playback resumes. While the
    /// server is asked for a stream, it waits for the answer (see `Reloading`).
    func reload() {
        guard !isStopped, !hasEnded, stream != nil, reloading.starts() else { return }
        let position = currentPosition
        // As the user left it; before it's under way, as the last load was going to.
        if isUnderWay {
            reloading.staysPaused = status == .paused
        }
        stopWatching()
        engine.pause()
        state = .loading
        let attempt = beginLoad()
        Task {
            await endSession(at: position)
            await load(allowsDirect: reloading.allowsDirect, from: position, as: attempt)
        }
    }
}
