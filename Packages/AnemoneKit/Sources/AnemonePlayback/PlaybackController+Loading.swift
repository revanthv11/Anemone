import AnemoneJellyfin

/// Loading streams: asking the server for the current entry's, retrying as a transcode, and
/// what happens at the end of an entry.
extension PlaybackController {
    func beginLoad() -> Int {
        reloading.isAsking = true
        loads += 1
        return loads
    }

    func load(allowsDirect: Bool, from position: Duration?, as attempt: Int) async {
        guard !isStopped else { return }
        let entry = queue.current
        // A new entry may need the other engine, as with "Prefer MPV"; a retry keeps it.
        if stream == nil, let engine = engine as? any PerEntryEngine {
            await engine.prepare(for: entry)
            guard !isStopped, attempt == loads else { return }
        }
        reloading.asks(allowsDirect: allowsDirect)
        var request = StreamRequest(itemID: entry.itemID, allowsDirect: allowsDirect, profile: engine.deviceProfile)
        // The version a retry or a reload keeps.
        request.mediaSourceID = stream?.mediaSourceID
        for feature in features {
            await feature.prepare(&request)
        }
        guard !isStopped, attempt == loads else { return }
        do {
            let stream = try await loadStream(request)
            guard !isStopped, attempt == loads, !reloading.asksAgain else {
                // Features never hear of a stream nothing plays, so a live stream it opened is closed here.
                await feature(LiveStreamClosing.self)?.discard(stream)
                // A reload that came meanwhile asks again.
                guard !isStopped, attempt == loads else { return }
                return await load(allowsDirect: allowsDirect, from: position, as: attempt)
            }
            await playLoaded(stream, of: entry, from: position)
        } catch {
            guard !isStopped, attempt == loads else { return }
            reloading.isAsking = false
            // An intro the server won't offer is passed over (Phase 5c).
            if let afterIntro = queue.afterIntroIndex {
                return play(entryAt: afterIntro)
            }
            state = .failed(error)
            await publish(.failed(error))
        }
    }

    private func playLoaded(_ stream: PlaybackStream, of entry: PlaybackQueue.Entry, from position: Duration?) async {
        self.stream = stream
        status = .paused
        isUnderWay = false
        wasPaused = false
        reloading.answered(startingAt: position ?? .zero)
        let events = engine.load(stream.url, from: position, metadata: entry.metadata)
        isSessionOpen = true
        await publish(reloading.hasReloaded ? .reloaded(stream) : .loaded(stream, entry))
        follow(events)
    }

    /// Wholphin's `onPlayerError`: a file that won't direct play or direct stream gets another
    /// try as a transcode, from where it stopped. A transcode that fails is an error.
    func failed(_ error: any Error) async {
        guard !isStopped, let stream else { return }
        stopWatching()
        let attempt = loads
        if stream.method != .transcode {
            // A reload while features hear of the failure asks for the transcode too.
            reloading.directFailed()
        }
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

    func finished() async {
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
}
