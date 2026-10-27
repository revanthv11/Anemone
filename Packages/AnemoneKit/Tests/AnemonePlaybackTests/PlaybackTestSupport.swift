import AnemoneJellyfin
@testable import AnemonePlayback
import Foundation
import JellyfinAPI
import QuartzCore
import Synchronization

/// An engine the test drives: it records what it's asked to load and sends the events the test
/// gives it. Like AVPlayer, it reports its status as soon as something loads.
@MainActor
final class FakeEngine: PlayerEngine {
    struct Load {
        let url: URL
        let position: Duration?
        let metadata: PlaybackMetadata
    }

    private(set) var loads: [Load] = []
    private(set) var isPlaying = false
    private(set) var isStopped = false
    var currentTime = Duration.zero
    var duration: Duration? = .seconds(100)
    var rate: Float = 1
    private var events: AsyncStream<PlayerEvent>.Continuation?

    var deviceProfile: DeviceProfile {
        DeviceProfile(name: "Fake")
    }

    var videoOutput: PlayerVideoOutput {
        .layer(CALayer())
    }

    func load(_ url: URL, from position: Duration?, metadata: PlaybackMetadata) -> AsyncStream<PlayerEvent> {
        events?.finish()
        let (stream, events) = AsyncStream.makeStream(of: PlayerEvent.self)
        self.events = events
        loads.append(Load(url: url, position: position, metadata: metadata))
        events.yield(.status(.paused))
        return stream
    }

    func send(_ event: PlayerEvent) {
        events?.yield(event)
    }

    func play() {
        isPlaying = true
        send(.status(.playing))
    }

    func pause() {
        isPlaying = false
        send(.status(.paused))
    }

    func stop() {
        isStopped = true
        events?.finish()
        events = nil
    }

    func seek(to position: Duration) async -> Bool {
        currentTime = position
        return true
    }

    func tracks(_: PlayerTrack.Kind) async -> [PlayerTrack] {
        []
    }

    func select(_: PlayerTrack?, _: PlayerTrack.Kind) async {}
}

/// A feature that writes down each event, and can act on one.
@MainActor
final class EventLog: PlaybackFeature {
    private(set) var events: [String] = []
    var onEvent: ((PlaybackEvent, PlaybackController) -> Void)?

    func handle(_ event: PlaybackEvent, in controller: PlaybackController) async {
        events.append(event.summary)
        onEvent?(event, controller)
    }
}

/// The server's side of `loadStream`: what it was asked for, and the streams it hands out.
final class FakeStreams: Sendable {
    struct Request: Equatable {
        let itemID: String
        let allowsDirect: Bool
        let mediaSourceID: String?
    }

    private let requests = Mutex<[Request]>([])
    private let failure: (any Error)?
    /// Items the server won't offer a stream for, when `failure` is `nil`.
    private let failingItems: Set<String>

    init(failingWith failure: (any Error)? = nil, failingItems: Set<String> = []) {
        self.failure = failure
        self.failingItems = failingItems
    }

    var received: [Request] {
        requests.withLock(\.self)
    }

    /// Direct play, or a transcode when direct play isn't allowed.
    var load: PlaybackController.StreamLoader {
        { [self] request in
            requests.withLock {
                $0.append(Request(
                    itemID: request.itemID,
                    allowsDirect: request.allowsDirect,
                    mediaSourceID: request.mediaSourceID,
                ))
            }
            if let failure {
                throw failure
            }
            if failingItems.contains(request.itemID) {
                throw PlaybackError.nothingToPlay
            }
            return Self.stream(request.itemID, method: request.allowsDirect ? .directPlay : .transcode)
        }
    }

    static func stream(_ itemID: String, method: PlaybackMethod) -> PlaybackStream {
        PlaybackStream(
            itemID: itemID,
            url: URL(filePath: "/\(itemID)/\(method)"),
            method: method,
            playSessionID: "ps-\(itemID)",
            mediaSourceID: "src-\(itemID)",
        )
    }
}

extension PlaybackQueue.Entry {
    static func item(_ id: String, from position: Duration? = nil) -> Self {
        Self(itemID: id, startPosition: position, metadata: PlaybackMetadata(title: "Title \(id)"))
    }
}

extension PlaybackEvent {
    /// Short enough to compare a whole run at once.
    var summary: String {
        switch self {
        case let .loaded(stream, entry): "loaded \(entry.itemID) \(stream.method)"
        case let .reloaded(stream): "reloaded \(stream.itemID) \(stream.method)"
        case let .started(progress): "started \(progress.position)"
        case .position: "position"
        case let .paused(progress): "paused \(progress.position)"
        case let .resumed(progress): "resumed \(progress.position)"
        case .ended: "ended"
        case .failed: "failed"
        case let .stopped(position): "stopped \(position)"
        }
    }
}

/// Waits for `condition`, giving the controller's tasks time to run; `false` after `timeout`.
@MainActor
func eventually(timeout: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else { return false }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return true
}
