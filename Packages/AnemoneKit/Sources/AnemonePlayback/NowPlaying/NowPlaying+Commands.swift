/// The remote's commands: which ones Now Playing offers, and what they do.
extension NowPlaying {
    /// Music's commands follow the player's queue; a video's, the controller's.
    func handleCommands(in controller: PlaybackController?) {
        let queue = controller?.queue
        guard let commands = music.map(Self.commands(for:)) ?? queue.map(Self.commands(for:)),
              commands != handledCommands
        else { return }
        handledCommands = commands
        slot.handle(commands, skipIntervals: (Self.skipForward, Self.skipBackward), by: self) { [weak self] in
            self?.perform($0) ?? false
        }
    }

    /// Next only when there's an entry after this one; Previous whenever the queue has several,
    /// since on the first entry it goes back to the start. Intros don't count, but Next during
    /// one moves on to what it leads into.
    static func commands(for queue: PlaybackQueue) -> Set<RemoteCommand> {
        var commands: Set<RemoteCommand> = [
            .play, .pause, .togglePlayPause, .skipForward, .skipBackward, .changePosition,
        ]
        if queue.countWithoutIntros > 1 {
            commands.insert(.previousTrack)
        }
        if queue.next != nil {
            commands.insert(.nextTrack)
        }
        return commands
    }

    /// For music, Next when the queue has a song after this one (or starts again); Previous always,
    /// since it goes back to the start of the song. No skips, so the system offers the track
    /// buttons, as it did before music moved onto this feature.
    static func commands(for player: MusicPlayer) -> Set<RemoteCommand> {
        var commands: Set<RemoteCommand> = [.play, .pause, .togglePlayPause, .changePosition, .previousTrack]
        if player.queue.nextIndex(automatic: false) != nil {
            commands.insert(.nextTrack)
        }
        return commands
    }

    /// What the remote asked for; `false` when it can't be done.
    private func perform(_ request: RemoteRequest) -> Bool {
        if isMusic {
            return music.map { perform(request, on: $0) } ?? false
        }
        guard let info, let controller else { return false }
        // Someone's there, so pass-out protection starts counting again.
        controller.feature(UpNext.self)?.noteRemoteInput()
        let engine = controller.engine
        switch request {
        case .play:
            engine.play()
        case .pause:
            engine.pause()
        case .togglePlayPause:
            return perform(info.isPlaying ? .pause : .play)
        case let .skip(offset):
            seek(to: engine.currentTime + offset)
        case let .seek(position):
            seek(to: position)
        case .next:
            guard controller.queue.next != nil else { return false }
            // The queue moves on through the controller, as Up Next does (Phase 3b).
            controller.playNext()
        case .previous:
            playPrevious(in: controller)
        }
        return true
    }

    /// Everything goes to the music player, which keeps the queue, and knows whether a song still
    /// loading should start once it's ready (`SongEngine`).
    private func perform(_ request: RemoteRequest, on player: MusicPlayer) -> Bool {
        switch request {
        case .play:
            player.resume()
        case .pause:
            player.pause()
        case .togglePlayPause:
            player.togglePlayPause()
        case let .skip(offset):
            // The player shows where it's going here at once.
            player.skip(by: offset)
        case let .seek(position):
            player.seek(to: position)
        case .next:
            guard player.queue.nextIndex(automatic: false) != nil else { return false }
            player.next()
        case .previous:
            player.previous()
        }
        return true
    }

    /// The entry before, passing over intros.
    private func playPrevious(in controller: PlaybackController) {
        if controller.engine.currentTime < Self.previousEntryWindow, let index = controller.queue.previousIndex {
            controller.play(entryAt: index)
        } else {
            seek(to: .zero)
        }
    }

    /// Within the video, and shown at once rather than at the next position event.
    private func seek(to position: Duration) {
        guard let engine = controller?.engine else { return }
        var target = max(position, .zero)
        if let duration = engine.duration {
            target = min(target, duration)
        }
        show(position: target)
        Task {
            _ = await engine.seek(to: target)
        }
    }
}
