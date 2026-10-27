import Foundation
import MediaPlayer
#if canImport(UIKit)
    import UIKit
#endif

/// The remote's commands that Now Playing can answer.
public enum RemoteCommand: CaseIterable, Hashable, Sendable {
    case play
    case pause
    case togglePlayPause
    case skipForward
    case skipBackward
    /// Scrubbing to a position, as the Remote app on a phone does.
    case changePosition
    case nextTrack
    case previousTrack
}

/// What a remote command asks the player to do.
public enum RemoteRequest: Hashable, Sendable {
    case play
    case pause
    case togglePlayPause
    /// Forward by a positive amount, back by a negative one.
    case skip(Duration)
    /// Scrubbing to a position.
    case seek(Duration)
    case next
    case previous
}

/// Where Now Playing goes: the system's info center and remote commands, or a test's record.
@MainActor
protocol NowPlayingCenter: AnyObject {
    /// Shows `info`, or clears Now Playing when `nil`.
    func publish(_ info: NowPlayingInfo?)
    /// Sends the remote's `commands` to `handler`, which returns whether it acted, and turns the
    /// other commands off.
    func handle(
        _ commands: Set<RemoteCommand>,
        skipIntervals: (forward: Duration, backward: Duration),
        with handler: @escaping @MainActor @Sendable (RemoteRequest) -> Bool,
    )
    /// Turns every command off.
    func stopHandling()
}

/// The app's `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter`. Adapted from Swiftfin's
/// `NowPlayableObserver` and `NowPlayableCommand`.
@MainActor
final class SystemNowPlayingCenter: NowPlayingCenter {
    private var targets: [(command: MPRemoteCommand, target: Any)] = []

    func publish(_ info: NowPlayingInfo?) {
        guard let info else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var properties = info.properties
        #if canImport(UIKit)
            if let image = info.artwork.flatMap(UIImage.init(data:)) {
                // Not on the main actor: MediaPlayer asks for the image on a queue of its own.
                properties[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in
                    image
                }
            }
        #endif
        MPNowPlayingInfoCenter.default().nowPlayingInfo = properties
    }

    func handle(
        _ commands: Set<RemoteCommand>,
        skipIntervals: (forward: Duration, backward: Duration),
        with handler: @escaping @MainActor @Sendable (RemoteRequest) -> Bool,
    ) {
        stopHandling()
        let center = MPRemoteCommandCenter.shared()
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: skipIntervals.forward / .seconds(1))]
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: skipIntervals.backward / .seconds(1))]
        for command in RemoteCommand.allCases {
            let remote = command.remote(in: center)
            remote.isEnabled = commands.contains(command)
            guard commands.contains(command) else { continue }
            let target = remote.addTarget { @Sendable event in
                // Read here, since the event isn't `Sendable`.
                guard let request = command.request(for: event) else { return .commandFailed }
                // The system calls on the main thread; Swiftfin hops there in case it doesn't.
                let acted = Thread.isMainThread
                    ? MainActor.assumeIsolated { handler(request) }
                    : DispatchQueue.main.sync { MainActor.assumeIsolated { handler(request) } }
                return acted ? .success : .commandFailed
            }
            targets.append((remote, target))
        }
    }

    func stopHandling() {
        for (command, target) in targets {
            command.removeTarget(target)
            command.isEnabled = false
        }
        targets = []
    }
}

private extension RemoteCommand {
    func remote(in center: MPRemoteCommandCenter) -> MPRemoteCommand {
        switch self {
        case .play: center.playCommand
        case .pause: center.pauseCommand
        case .togglePlayPause: center.togglePlayPauseCommand
        case .skipForward: center.skipForwardCommand
        case .skipBackward: center.skipBackwardCommand
        case .changePosition: center.changePlaybackPositionCommand
        case .nextTrack: center.nextTrackCommand
        case .previousTrack: center.previousTrackCommand
        }
    }

    /// `nil` for an event that doesn't make sense, such as a skip of no time.
    func request(for event: MPRemoteCommandEvent) -> RemoteRequest? {
        switch self {
        case .play:
            return .play
        case .pause:
            return .pause
        case .togglePlayPause:
            return .togglePlayPause
        case .skipForward, .skipBackward:
            guard let event = event as? MPSkipIntervalCommandEvent, event.interval.isFinite, event.interval > 0 else {
                return nil
            }
            return .skip(.seconds(self == .skipForward ? event.interval : -event.interval))
        case .changePosition:
            guard let event = event as? MPChangePlaybackPositionCommandEvent, event.positionTime.isFinite else {
                return nil
            }
            return .seek(.seconds(max(event.positionTime, 0)))
        case .nextTrack:
            return .next
        case .previousTrack:
            return .previous
        }
    }
}
