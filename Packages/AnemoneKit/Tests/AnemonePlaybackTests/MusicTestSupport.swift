import AnemoneJellyfin
@testable import AnemonePlayback
import Foundation
import Synchronization

/// The server's side of song streams: what was asked for, and whether it fails.
final class SongStreams: Sendable {
    struct Request: Equatable {
        let songID: String
        let allowsDirect: Bool
    }

    private let requests = Mutex<[Request]>([])
    private let failing = Mutex(false)

    var fail: Bool {
        get { failing.withLock(\.self) }
        set { failing.withLock { $0 = newValue } }
    }

    var received: [Request] {
        requests.withLock(\.self)
    }

    var load: MusicPlayer.StreamLoader {
        { [self] song, allowsDirect in
            requests.withLock { $0.append(Request(songID: song.id, allowsDirect: allowsDirect)) }
            if fail {
                throw PlaybackError.nothingToPlay
            }
            return FakeStreams.stream(song.id, method: allowsDirect ? .directPlay : .transcode)
        }
    }
}

/// The server's side of song lists.
final class FakeLibrary: Sendable {
    struct Request: Equatable {
        let source: MusicSource
        let shuffled: Bool
        let startIndex: Int
        let limit: Int
    }

    private let stored = Mutex<[MusicItem]>([])
    private let requests = Mutex<[Request]>([])
    private let failing = Mutex<Int?>(nil)
    private let holding = Mutex<LoadGate?>(nil)

    var songs: [MusicItem] {
        get { stored.withLock(\.self) }
        set { stored.withLock { $0 = newValue } }
    }

    /// Pages from this index on fail.
    var failsFrom: Int? {
        get { failing.withLock(\.self) }
        set { failing.withLock { $0 = newValue } }
    }

    /// Pages wait for this gate to open.
    var gate: LoadGate? {
        get { holding.withLock(\.self) }
        set { holding.withLock { $0 = newValue } }
    }

    var received: [Request] {
        requests.withLock(\.self)
    }

    var load: MusicPlayer.SongLoader {
        { [self] source, shuffled, startIndex, limit in
            requests.withLock {
                $0.append(Request(source: source, shuffled: shuffled, startIndex: startIndex, limit: limit))
            }
            await gate?.wait()
            if let failsFrom, startIndex >= failsFrom {
                throw PlaybackError.nothingToPlay
            }
            let all = songs
            let page = Array(all.dropFirst(startIndex).prefix(limit))
            return MusicPage(items: page, totalCount: startIndex == 0 ? all.count : nil)
        }
    }
}

/// Holds loads until the test opens it, so the test can act while a load is out.
final class LoadGate: Sendable {
    private struct State {
        var isOpen = false
        var isReached = false
        var waiting: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())

    /// Whether a load has reached the gate.
    var isReached: Bool {
        state.withLock(\.isReached)
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            let isOpen = state.withLock {
                $0.isReached = true
                if !$0.isOpen {
                    $0.waiting.append(continuation)
                }
                return $0.isOpen
            }
            if isOpen {
                continuation.resume()
            }
        }
    }

    func open() {
        let waiting = state.withLock {
            $0.isOpen = true
            let waiting = $0.waiting
            $0.waiting = []
            return waiting
        }
        for continuation in waiting {
            continuation.resume()
        }
    }
}

/// A feature whose `stopped` waits for the test, like a stop report to a slow server.
@MainActor
final class SlowStop: PlaybackFeature {
    let gate = LoadGate()

    func handle(_ event: PlaybackEvent, in _: PlaybackController) async {
        if case .stopped = event {
            await gate.wait()
        }
    }
}
