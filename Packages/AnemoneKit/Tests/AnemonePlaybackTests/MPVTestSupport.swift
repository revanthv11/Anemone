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
    /// Takes `loadfile` without saying which playlist entry it made.
    var hidesEntries = false
    /// Commands, by name, that fail, as `seek` does with nothing to seek in.
    var refusedCommands: Set<String> = []
    private(set) var isDestroyed = false

    init() {
        (events, continuation) = AsyncStream.makeStream(of: MPVEvent.self)
    }

    func set(_ name: String, _ value: String) {
        sets.append((name, value))
        properties[name] = value
    }

    func command(_ arguments: [String]) -> Bool {
        commands.append(arguments)
        guard let name = arguments.first, !refusedCommands.contains(name) else { return false }
        if name == "sub-add" {
            addTrack(subAdd: arguments)
        }
        return true
    }

    /// The IDs of the commands sent with `commandAsync`, oldest first, for the replies a test
    /// hands the engine.
    private(set) var asyncIDs: [UInt64] = []

    func commandAsync(_ arguments: [String], id: UInt64) -> Bool {
        commands.append(arguments)
        guard let name = arguments.first, !refusedCommands.contains(name) else { return false }
        asyncIDs.append(id)
        return true
    }

    func loadFile(_ arguments: [String]) -> MPVLoadResult {
        commands.append(arguments)
        guard !refusesLoads else { return .refused }
        // libmpv numbers entries from 1 and never reuses one.
        let entry = Int64(entries.count + 1)
        entries.append(entry)
        return .started(entry: hidesEntries ? nil : entry)
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
        var codec: String?
        /// Added beside the file with `sub-add`.
        var external = false
    }

    private(set) var tracks: [Track] = []

    /// Lists tracks the way libmpv's `track-list` sub-properties do.
    func list(_ tracks: [Track]) {
        self.tracks = tracks
        properties["track-list/count"] = String(tracks.count)
        for (index, track) in tracks.enumerated() {
            properties["track-list/\(index)/type"] = track.type
            properties["track-list/\(index)/id"] = String(track.id)
            properties["track-list/\(index)/title"] = track.title
            properties["track-list/\(index)/lang"] = track.lang
            properties["track-list/\(index)/selected"] = track.selected ? "yes" : "no"
            properties["track-list/\(index)/codec"] = track.codec
            properties["track-list/\(index)/external"] = track.external ? "yes" : "no"
        }
    }

    /// `sub-add <url> <flags> [title [lang]]` adds a subtitle track after the others, selected
    /// with `select`, as libmpv does.
    private func addTrack(subAdd arguments: [String]) {
        let selects = arguments.count > 2 && arguments[2] == "select"
        var tracks = tracks
        if selects {
            for index in tracks.indices where tracks[index].type == "sub" {
                tracks[index].selected = false
            }
        }
        let id = (tracks.filter { $0.type == "sub" }.map(\.id).max() ?? 0) + 1
        let title = arguments.count > 3 ? arguments[3] : nil
        let lang = arguments.count > 4 ? arguments[4] : nil
        tracks.append(Track(type: "sub", id: id, title: title, lang: lang, selected: selects, external: true))
        list(tracks)
    }
}

/// Time for the MPV engine's seek timeouts that passes only when the test says.
@MainActor
final class ManualTime {
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// How many timeouts are running.
    var running: Int {
        waiting.count
    }

    func wait(_: Duration) async {
        await withCheckedContinuation { waiting.append($0) }
    }

    /// Ends every timeout running.
    func pass() {
        let ended = waiting
        waiting = []
        ended.forEach { $0.resume() }
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
    /// An engine on `client`, whose seek timeouts pass when `time` says, if given.
    static func testing(_ client: FakeMPVClient?, time: ManualTime? = nil) -> MPVPlayerEngine {
        let seeks = time.map { time in MPVSeeks { await time.wait($0) } } ?? MPVSeeks()
        return MPVPlayerEngine(client: client, layer: CALayer(), profile: MPVProfile.deviceProfile(), seeks: seeks)
    }

    /// A load of a file from its beginning, with what its events say.
    func loadLog(_ path: String = "/m.mkv") -> PlayerEventLog {
        PlayerEventLog(load(URL(filePath: path), from: nil, metadata: PlaybackMetadata(title: "M")))
    }

    /// Loads a file as libmpv would through `client`, this engine's: the file starts, loads, and
    /// plays from its start.
    func loadAndStart(on client: FakeMPVClient, _ path: String = "/m.mkv") -> PlayerEventLog {
        let log = loadLog(path)
        start(client.entries.last ?? 0)
        return log
    }

    /// libmpv's reply to the newest command sent to `client` with `commandAsync`, such as a seek:
    /// it took it, or refused it.
    func reply(on client: FakeMPVClient, succeeded: Bool = true) {
        guard let id = client.asyncIDs.last else { return }
        handle(.commandReply(id: id, succeeded: succeeded))
    }

    /// libmpv's events as it starts, opens and plays `entry`.
    func start(_ entry: Int64) {
        handle(.startFile(entry: entry))
        handle(.fileLoaded(entry: entry))
        handle(.playbackRestart(entry: entry))
    }
}
