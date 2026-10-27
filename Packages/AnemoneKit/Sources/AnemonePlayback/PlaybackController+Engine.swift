/// Following the engine: what it says about the loaded stream becomes the controller's state
/// and its features' events.
extension PlaybackController {
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
        reloading.pendingStart = nil
        guard !isStopped else { return }
        state = .playing
        guard !reloading.staysPaused else { return }
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
            reloading.staysPaused = false
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

    func stopWatching() {
        watchers.forEach { $0.cancel() }
        watchers = []
    }
}
