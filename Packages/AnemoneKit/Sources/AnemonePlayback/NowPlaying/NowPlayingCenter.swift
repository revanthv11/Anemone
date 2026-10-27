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
/// `NowPlayableObserver` and `NowPlayableCommand`. There's one, in `NowPlaying.Slot.shared`, so the
/// targets it adds are the only ones, whichever player added them.
@MainActor
final class SystemNowPlayingCenter: NowPlayingCenter {
    /// Turns image data into the system's artwork, an `MPMediaItemArtwork`.
    typealias ArtworkMaker = @MainActor (Data) -> AnyObject?
    /// Hands the properties to `MPNowPlayingInfoCenter`.
    typealias Writer = @MainActor ([String: Any]?) -> Void

    private let makeArtwork: ArtworkMaker
    private let write: Writer
    private var targets: [(command: MPRemoteCommand, target: Any)] = []
    /// What's shown, and the properties that show it, artwork included.
    private var shown: NowPlayingInfo?
    private var properties: [String: Any] = [:]

    init(
        makeArtwork: @escaping ArtworkMaker = SystemNowPlayingCenter.artwork(from:),
        write: @escaping Writer = { MPNowPlayingInfoCenter.default().nowPlayingInfo = $0 },
    ) {
        self.makeArtwork = makeArtwork
        self.write = write
    }

    /// Builds the properties, artwork and all, once per entry (and again when its artwork
    /// arrives); after that, the position updates only change the timing.
    func publish(_ info: NowPlayingInfo?) {
        guard let info else {
            shown = nil
            properties = [:]
            write(nil)
            return
        }
        if shown.map({ !$0.showsSameEntry(as: info) }) ?? true {
            properties = info.entryProperties
            if let artwork = info.artwork.flatMap({ makeArtwork($0.data) }) {
                properties[MPMediaItemPropertyArtwork] = artwork
            }
        }
        shown = info
        info.setTiming(in: &properties)
        write(properties)
    }

    /// Decodes the image once; MediaPlayer then asks the artwork for it on a queue of its own,
    /// not on the main actor.
    static func artwork(from data: Data) -> AnyObject? {
        #if canImport(UIKit)
            guard let image = UIImage(data: data) else { return nil }
            return MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
        #else
            return nil
        #endif
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
