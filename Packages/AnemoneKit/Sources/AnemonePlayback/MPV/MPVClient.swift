import Foundation

/// What the MPV engine needs from libmpv: options and properties by name, commands, and the
/// events it sends. `LibMPVClient` is the real one; tests stand in their own, so the engine runs
/// on macOS without libmpv.
@MainActor
protocol MPVClient: AnyObject {
    /// What libmpv sends, in order, until the client is destroyed.
    var events: AsyncStream<MPVEvent> { get }

    /// Sets a property, or an option before the file loads, as `--name=value` would.
    func set(_ name: String, _ value: String)
    /// Runs a command such as `seek`, as an input.conf line would, and says whether libmpv
    /// took it.
    @discardableResult
    func command(_ arguments: [String]) -> Bool
    /// Runs a command such as `seek` without waiting for it, and says whether libmpv queued it.
    /// libmpv answers with a `commandReply` event naming `id`, which comes after what it said
    /// before running the command and before what it says about what the command started.
    @discardableResult
    func commandAsync(_ arguments: [String], id: UInt64) -> Bool
    /// Runs `loadfile`, saying which playlist entry libmpv made for the file, or that it
    /// refused the command.
    func loadFile(_ arguments: [String]) -> MPVLoadResult
    /// A property's value as text, or `nil` when it has none now, such as `time-pos` with
    /// nothing loaded.
    func string(_ name: String) -> String?
    /// Tears down libmpv; nothing works after this.
    func destroy()
}

extension MPVClient {
    func double(_ name: String) -> Double? {
        string(name).flatMap(Double.init)
    }

    func int(_ name: String) -> Int? {
        string(name).flatMap { Int($0) }
    }

    /// libmpv's flags read "yes" or "no".
    func flag(_ name: String) -> Bool? {
        string(name).map { $0 == "yes" }
    }

    func set(_ name: String, _ value: Bool) {
        set(name, value ? "yes" : "no")
    }

    func set(_ name: String, _ value: Double) {
        set(name, String(value))
    }

    func set(_ name: String, _ value: Int) {
        set(name, String(value))
    }
}

/// What `loadfile` did.
enum MPVLoadResult: Equatable, Sendable {
    /// libmpv took the file as a playlist entry, whose ID its events about the file carry; `nil`
    /// when libmpv didn't say which.
    case started(entry: Int64?)
    /// libmpv refused the command, as it does arguments it can't parse.
    case refused
}

/// What libmpv sends, reduced to what the engine follows. Events about a file name its
/// playlist entry, so what libmpv says about a file that a newer load replaced isn't taken for
/// the new one's.
enum MPVEvent: Equatable, Sendable {
    /// libmpv began opening a playlist entry. What it says from here until the entry ends is
    /// about this one.
    case startFile(entry: Int64)
    /// The entry's file was opened, and decoding starts.
    case fileLoaded(entry: Int64)
    /// libmpv started a seek in the entry; a playback restart follows once it lands. It doesn't
    /// say which seek: the newest whose `commandReply` came before it (see `MPVSeeks`).
    case seek(entry: Int64)
    /// Playback of the entry restarted after loading or after a seek: the picture is at the
    /// new position.
    case playbackRestart(entry: Int64)
    /// The entry was unloaded: it failed (with libmpv's reason), something replaced or stopped
    /// it, or it was a playlist. A file that won't open fails this way without ever loading.
    /// With `keep-open`, reaching the end doesn't unload it; `eof-reached` says so.
    case endFile(entry: Int64, MPVEndReason)
    /// libmpv ran the command sent with `commandAsync` as `id`, or refused it.
    case commandReply(id: UInt64, succeeded: Bool)
    /// An observed property changed; see `LibMPVClient.observed`.
    case property(String, MPVValue)
    /// libmpv is shutting down.
    case shutdown
}

enum MPVEndReason: Equatable, Sendable {
    case endOfFile
    /// A command such as `stop`, or another `loadfile`, ended it.
    case stopped
    /// libmpv is shutting down.
    case quit
    /// The file was a playlist: libmpv put its entries in its place and plays on from `next`,
    /// the first of them, or from nothing when it had none.
    case redirected(next: Int64?)
    case failed(String)
}

/// An observed property's new value. Flags arrive as `flag`, numbers as `double`; `none` means
/// the property has no value now, such as `duration` once the file is gone.
enum MPVValue: Equatable, Sendable {
    case none
    case flag(Bool)
    case double(Double)
    case string(String)

    var flag: Bool? {
        if case let .flag(value) = self {
            value
        } else {
            nil
        }
    }

    var double: Double? {
        if case let .double(value) = self {
            value
        } else {
            nil
        }
    }
}

/// Why libmpv couldn't play what the server sent, in libmpv's words, for the player's message.
public struct MPVError: LocalizedError, Equatable {
    public let reason: String

    public init(reason: String) {
        self.reason = reason
    }

    /// libmpv itself couldn't start.
    public static let unavailable = Self(reason: String(localized: "The MPV player couldn't start.", bundle: .module))
    /// libmpv wouldn't take the stream to load.
    public static let refused = Self(reason: String(
        localized: "The MPV player couldn't load the stream.",
        bundle: .module,
    ))
    /// libmpv stopped the stream without being asked to, such as while shutting down.
    public static let stopped = Self(reason: String(localized: "The MPV player stopped the stream.", bundle: .module))
    /// The stream was a playlist with nothing in it.
    public static let emptyPlaylist = Self(reason: String(
        localized: "The stream was an empty playlist.",
        bundle: .module,
    ))
    /// The stream ran out well before its duration, as when the connection drops: with
    /// `keep-open`, libmpv reports that as the end of the file.
    public static let endedEarly = Self(reason: String(
        localized: "The stream stopped before its end.",
        bundle: .module,
    ))

    public var errorDescription: String? {
        reason
    }
}
