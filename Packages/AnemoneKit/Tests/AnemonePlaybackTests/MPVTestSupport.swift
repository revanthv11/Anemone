@testable import AnemonePlayback
import Foundation
import QuartzCore

/// libmpv as the test plays it: properties the test sets, and a record of what the engine set
/// and ran. Tests hand events to the engine with `MPVPlayerEngine.handle(_:)`.
@MainActor
final class FakeMPVClient: MPVClient {
    let events: AsyncStream<MPVEvent>
    private let continuation: AsyncStream<MPVEvent>.Continuation
    var properties: [String: String] = [:]
    private(set) var sets: [(name: String, value: String)] = []
    private(set) var commands: [[String]] = []
    /// The playlist entry IDs given to the files loaded, oldest first; libmpv's start-file and
    /// end-file events name them.
    private(set) var entries: [Int64] = []
    /// Refuses `loadfile`, as libmpv does with arguments it can't parse.
    var refusesLoads = false
    private(set) var isDestroyed = false

    init() {
        (events, continuation) = AsyncStream.makeStream(of: MPVEvent.self)
    }

    func set(_ name: String, _ value: String) {
        sets.append((name, value))
        properties[name] = value
    }

    func command(_ arguments: [String]) {
        commands.append(arguments)
    }

    func loadFile(_ arguments: [String]) -> Int64? {
        commands.append(arguments)
        guard !refusesLoads else { return nil }
        // libmpv numbers entries from 1 and never reuses one.
        let entry = Int64(entries.count + 1)
        entries.append(entry)
        return entry
    }

    func string(_ name: String) -> String? {
        properties[name]
    }

    func destroy() {
        isDestroyed = true
        continuation.finish()
    }

    /// The last value the engine set for `name`.
    func lastSet(_ name: String) -> String? {
        sets.last { $0.name == name }?.value
    }

    struct Track {
        var type: String
        var id: Int
        var title: String?
        var lang: String?
        var selected = false
    }

    /// Lists tracks the way libmpv's `track-list` sub-properties do.
    func list(_ tracks: [Track]) {
        properties["track-list/count"] = String(tracks.count)
        for (index, track) in tracks.enumerated() {
            properties["track-list/\(index)/type"] = track.type
            properties["track-list/\(index)/id"] = String(track.id)
            properties["track-list/\(index)/title"] = track.title
            properties["track-list/\(index)/lang"] = track.lang
            properties["track-list/\(index)/selected"] = track.selected ? "yes" : "no"
        }
    }
}

/// Collects what a load's events say, as they come.
@MainActor
final class PlayerEventLog {
    private(set) var events: [String] = []
    private(set) var isFinished = false
    private(set) var errors: [any Error] = []

    init(_ stream: AsyncStream<PlayerEvent>) {
        Task { @MainActor in
            for await event in stream {
                switch event {
                case .ready: events.append("ready")
                case let .status(status): events.append("\(status)")
                case .ended: events.append("ended")
                case let .failed(error):
                    events.append("failed")
                    errors.append(error)
                }
            }
            isFinished = true
        }
    }
}

extension MPVPlayerEngine {
    static func testing(_ client: FakeMPVClient?) -> MPVPlayerEngine {
        MPVPlayerEngine(client: client, layer: CALayer(), profile: MPVProfile.deviceProfile())
    }

    /// A load of a file from its beginning, with what its events say.
    func loadLog() -> PlayerEventLog {
        PlayerEventLog(load(URL(filePath: "/m.mkv"), from: nil, metadata: PlaybackMetadata(title: "M")))
    }

    /// Loads a file as libmpv would through `client`, this engine's: the file starts, loads, and
    /// plays from its start.
    func loadAndStart(on client: FakeMPVClient) -> PlayerEventLog {
        let log = loadLog()
        handle(.startFile(entry: client.entries.last ?? 0))
        handle(.playbackRestart)
        return log
    }
}
