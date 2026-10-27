import Foundation

/// An audio or subtitle stream in an item's file, as the server describes it: what choosing
/// tracks by language and flags reads, and how the server sends a subtitle. The parts of
/// Jellyfin's `MediaStream` that Wholphin's `StreamChoiceService` uses.
public struct MediaTrack: Hashable, Sendable, Identifiable {
    public enum Kind: String, Hashable, Sendable, Codable {
        case audio
        case subtitle
    }

    /// How the server sends a subtitle with the stream it offered.
    public enum Delivery: Hashable, Sendable {
        /// Inside the file the player plays directly.
        case embedded
        /// As WebVTT in the HLS playlist.
        case hls
        /// As a file of its own.
        case external
        /// Drawn into the video by a transcode.
        case burnedIn
        /// Not sent at all.
        case dropped
    }

    /// The server's index for the stream, which PlaybackInfo and progress reports use.
    public let index: Int
    public let kind: Kind
    /// An ISO 639-2 code such as `eng` or `fre`, as the file tags it.
    public var language: String?
    /// The stream's own title, such as "Signs & Songs".
    public var title: String?
    /// The server's label, such as "English - AAC - Stereo - Default".
    public var displayTitle: String?
    public var codec: String?
    public var channels: Int?
    public var isDefault: Bool
    public var isForced: Bool
    public var isHearingImpaired: Bool
    public var isExternal: Bool
    /// For subtitles: text (SRT, ASS, WebVTT) rather than pictures (PGS, DVD).
    public var isText: Bool
    /// For subtitles, once the server has said how it sends them.
    public var delivery: Delivery?

    public var id: Int {
        index
    }

    public init(
        index: Int,
        kind: Kind,
        language: String? = nil,
        title: String? = nil,
        displayTitle: String? = nil,
        codec: String? = nil,
        channels: Int? = nil,
        isDefault: Bool = false,
        isForced: Bool = false,
        isHearingImpaired: Bool = false,
        isExternal: Bool = false,
        isText: Bool = true,
        delivery: Delivery? = nil,
    ) {
        self.index = index
        self.kind = kind
        self.language = language
        self.title = title
        self.displayTitle = displayTitle
        self.codec = codec
        self.channels = channels
        self.isDefault = isDefault
        self.isForced = isForced
        self.isHearingImpaired = isHearingImpaired
        self.isExternal = isExternal
        self.isText = isText
        self.delivery = delivery
    }

    /// A signs-and-songs track that isn't flagged as forced, found by its title as Wholphin does.
    public var isSigns: Bool {
        guard let title = title ?? displayTitle else { return false }
        return ["forced", "signs", "songs"].contains { title.localizedCaseInsensitiveContains($0) }
    }

    /// Forced by its flag or its title: Wholphin's `isForcedOrSigns`.
    public var isForcedOrSigns: Bool {
        isForced || isSigns
    }

    /// ASS and SSA subtitles, whose positioning and styling only a renderer such as libass
    /// shows. AVPlayer gets them as plain WebVTT, so Anemone has the server burn them in; MPV
    /// (Phase 4) draws them itself.
    public var isStyledText: Bool {
        kind == .subtitle && ["ass", "ssa"].contains(codec?.lowercased())
    }

    /// Picture subtitles such as PGS and DVD, which AVPlayer can't show, so the server burns them
    /// in; MPV (Phase 4) draws them itself.
    public var isPicture: Bool {
        kind == .subtitle && !isText
    }
}

/// What a remembered choice says about the track it was made on, so a similar track can be
/// found in the next episode. Wholphin's `TrackFlag`, with its stored values.
public struct TrackFlags: OptionSet, Hashable, Sendable, Codable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let isDefault = Self(rawValue: 1)
    public static let forced = Self(rawValue: 2)
    public static let hearingImpaired = Self(rawValue: 4)
    public static let external = Self(rawValue: 8)
    public static let signs = Self(rawValue: 16)

    public init(_ track: MediaTrack) {
        var flags: Self = []
        if track.isDefault {
            flags.insert(.isDefault)
        }
        if track.isForced {
            flags.insert(.forced)
        }
        if track.isHearingImpaired {
            flags.insert(.hearingImpaired)
        }
        if track.isExternal {
            flags.insert(.external)
        }
        if track.isSigns {
            flags.insert(.signs)
        }
        self = flags
    }
}

public extension [MediaTrack] {
    /// The tracks of one kind, in the server's order.
    func of(_ kind: MediaTrack.Kind) -> [MediaTrack] {
        filter { $0.kind == kind }
    }

    /// Each track's position among the tracks of its kind that are, like it, in the file or
    /// beside it: what Wholphin's `RelativeMediaStream` remembers, since the server's indices
    /// shift from one episode to the next.
    func relativeIndex(of track: MediaTrack) -> Int? {
        filter { $0.kind == track.kind && $0.isExternal == track.isExternal }
            .sorted { $0.index < $1.index }
            .firstIndex { $0.index == track.index }
    }
}
