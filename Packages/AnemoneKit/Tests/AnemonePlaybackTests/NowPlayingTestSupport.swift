@testable import AnemonePlayback
import Foundation
import Synchronization

/// What `SystemNowPlayingCenter` made and handed to the system.
@MainActor
final class FakeSystem {
    var artworks: [NSObject] = []
    var written: [[String: Any]?] = []
}

/// Records what Now Playing would show, and stands in for the remote.
@MainActor
final class FakeCenter: NowPlayingCenter {
    private(set) var published: [NowPlayingInfo?] = []
    private(set) var commands: Set<RemoteCommand> = []

    /// What the system shows now.
    var shown: NowPlayingInfo? {
        published.last ?? nil
    }

    private(set) var skipIntervals: (forward: Duration, backward: Duration)?
    private var handler: (@MainActor (RemoteRequest) -> Bool)?

    var isHandling: Bool {
        handler != nil
    }

    func publish(_ info: NowPlayingInfo?) {
        published.append(info)
    }

    func handle(
        _ commands: Set<RemoteCommand>,
        skipIntervals: (forward: Duration, backward: Duration),
        with handler: @escaping @MainActor @Sendable (RemoteRequest) -> Bool,
    ) {
        self.commands = commands
        self.skipIntervals = skipIntervals
        self.handler = handler
    }

    func stopHandling() {
        commands = []
        handler = nil
    }

    /// A press on the remote; `false` when nothing handled it.
    func send(_ request: RemoteRequest) -> Bool {
        handler?(request) ?? false
    }
}

/// The artwork Now Playing asked for.
final class ArtworkRequests: Sendable {
    private let requests = Mutex<[URL]>([])

    var urls: [URL] {
        requests.withLock(\.self)
    }

    func append(_ url: URL) {
        requests.withLock { $0.append(url) }
    }
}
