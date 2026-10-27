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

    var songs: [MusicItem] {
        get { stored.withLock(\.self) }
        set { stored.withLock { $0 = newValue } }
    }

    /// Pages from this index on fail.
    var failsFrom: Int? {
        get { failing.withLock(\.self) }
        set { failing.withLock { $0 = newValue } }
    }

    var received: [Request] {
        requests.withLock(\.self)
    }

    var load: MusicPlayer.SongLoader {
        { [self] source, shuffled, startIndex, limit in
            requests.withLock {
                $0.append(Request(source: source, shuffled: shuffled, startIndex: startIndex, limit: limit))
            }
            if let failsFrom, startIndex >= failsFrom {
                throw PlaybackError.nothingToPlay
            }
            let all = songs
            let page = Array(all.dropFirst(startIndex).prefix(limit))
            return MusicPage(items: page, totalCount: startIndex == 0 ? all.count : nil)
        }
    }
}

/// A remote that writes down what it hears.
@MainActor
final class RecordingRemote: MusicRemote {
    private(set) var attached = false
    private(set) var detached = false
    private(set) var statuses: [MusicPlayer.Status] = []

    func attach(to _: MusicPlayer) {
        attached = true
    }

    func update(from player: MusicPlayer) {
        statuses.append(player.status)
    }

    func detach() {
        detached = true
    }
}
