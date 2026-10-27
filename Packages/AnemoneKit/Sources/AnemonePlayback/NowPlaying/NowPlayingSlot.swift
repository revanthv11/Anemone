extension NowPlaying {
    /// The system's one Now Playing and set of remote commands, which every player's `NowPlaying`
    /// goes through, as every player's display matching goes through one display
    /// (`DisplayCriteriaMatching.Display`). The feature that published last owns it, and only the
    /// owner can clear it: a player whose `stopped` comes late, after the next player or song has
    /// loaded, leaves the new one's Now Playing and commands alone.
    @MainActor
    final class Slot {
        static let shared = Slot(center: SystemNowPlayingCenter())

        private let center: any NowPlayingCenter
        /// The feature that published last.
        private weak var owner: NowPlaying?

        init(center: any NowPlayingCenter) {
            self.center = center
        }

        /// Shows `info` for `feature`, which owns Now Playing from now on.
        func publish(_ info: NowPlayingInfo, by feature: NowPlaying) {
            owner = feature
            center.publish(info)
        }

        /// Sends the remote's `commands` to `handler` for `feature`, which owns Now Playing from
        /// now on, and turns the other commands off.
        func handle(
            _ commands: Set<RemoteCommand>,
            skipIntervals: (forward: Duration, backward: Duration),
            by feature: NowPlaying,
            with handler: @escaping @MainActor @Sendable (RemoteRequest) -> Bool,
        ) {
            owner = feature
            center.handle(commands, skipIntervals: skipIntervals, with: handler)
        }

        /// Hands Now Playing to the system player, which publishes it and answers the remote itself:
        /// what another player left is cleared, and that player can't clear the system player's.
        func yield(to feature: NowPlaying) {
            if let owner, owner !== feature {
                clear()
            }
            owner = feature
        }

        /// Clears Now Playing and turns every command off, unless another feature has published
        /// since `feature` did.
        func release(by feature: NowPlaying) {
            guard owner === feature else { return }
            owner = nil
            clear()
        }

        private func clear() {
            center.stopHandling()
            center.publish(nil)
        }
    }
}
