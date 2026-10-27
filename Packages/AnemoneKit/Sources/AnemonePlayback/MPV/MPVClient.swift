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
    /// Runs a command such as `loadfile` or `seek`, as an input.conf line would.
    func command(_ arguments: [String])
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

/// What libmpv sends, reduced to what the engine follows.
enum MPVEvent: Equatable, Sendable {
    /// A file opened; its tracks and duration are known.
    case fileLoaded
    /// Playback restarted after loading or after a seek: the picture is at the new position.
    case playbackRestart
    /// The file was unloaded: it failed (with libmpv's reason), or something replaced or
    /// stopped it. With `keep-open`, reaching the end doesn't unload it; `eof-reached` says so.
    case endFile(MPVEndReason)
    /// An observed property changed; see `LibMPVClient.observed`.
    case property(String, MPVValue)
    /// libmpv is shutting down.
    case shutdown
}

enum MPVEndReason: Equatable, Sendable {
    case endOfFile
    case stopped
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
    public static let unavailable = Self(reason: "The MPV player couldn't start.")

    public var errorDescription: String? {
        reason
    }
}
