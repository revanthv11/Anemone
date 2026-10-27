import Foundation

/// The subtitles the user picked for an item. Wholphin's special `TrackIndex` values.
public enum SubtitleChoice: Hashable, Sendable, Codable {
    case off
    /// Forced subtitles in the preferred or the audio's language, found again when the audio
    /// changes.
    case onlyForced
    case track(index: Int)
}

/// The tracks the user picked for one item, which win over everything else the next time it
/// plays. Wholphin's `ItemPlayback`.
public struct ItemTrackChoice: Hashable, Sendable, Codable {
    public let itemID: String
    /// The version the indices belong to; another version's tracks are numbered differently.
    public var mediaSourceID: String?
    /// `nil` when the user hasn't picked audio.
    public var audioIndex: Int?
    /// `nil` when the user hasn't picked subtitles.
    public var subtitle: SubtitleChoice?

    public init(itemID: String, mediaSourceID: String?, audioIndex: Int? = nil, subtitle: SubtitleChoice? = nil) {
        self.itemID = itemID
        self.mediaSourceID = mediaSourceID
        self.audioIndex = audioIndex
        self.subtitle = subtitle
    }
}

/// A choice remembered for a season or a whole series, so the next episode gets a similar
/// track: the language, flags and position of the one picked. Wholphin's `SeriesTrackChoice`.
public struct SeriesTrackChoice: Hashable, Sendable, Codable {
    public enum Parent: String, Hashable, Sendable, Codable {
        case season
        case series
    }

    public enum Activation: String, Hashable, Sendable, Codable {
        case activated
        /// Subtitles off.
        case disabled
        case onlyForced
    }

    /// The season's or series' ID.
    public var parentID: String
    public var parent: Parent
    public var kind: MediaTrack.Kind
    /// The episode it was picked in.
    public var itemID: String?
    public var language: String?
    public var activation: Activation
    public var flags: TrackFlags
    public var codec: String?
    /// The track's position among its kind; see `[MediaTrack].relativeIndex(of:)`.
    public var relativeIndex: Int?
    public var title: String?
    public var channels: Int?

    public init(
        parentID: String,
        parent: Parent,
        kind: MediaTrack.Kind,
        itemID: String? = nil,
        language: String? = nil,
        activation: Activation = .activated,
        flags: TrackFlags = [],
        codec: String? = nil,
        relativeIndex: Int? = nil,
        title: String? = nil,
        channels: Int? = nil,
    ) {
        self.parentID = parentID
        self.parent = parent
        self.kind = kind
        self.itemID = itemID
        self.language = language
        self.activation = activation
        self.flags = flags
        self.codec = codec
        self.relativeIndex = relativeIndex
        self.title = title
        self.channels = channels
    }

    /// What to remember of `track`, picked in `itemID` among `tracks`.
    public init(
        parentID: String,
        parent: Parent,
        itemID: String,
        track: MediaTrack,
        among tracks: [MediaTrack],
    ) {
        self.init(
            parentID: parentID,
            parent: parent,
            kind: track.kind,
            itemID: itemID,
            language: track.language,
            flags: TrackFlags(track),
            codec: track.codec,
            relativeIndex: tracks.relativeIndex(of: track),
            title: track.title,
            channels: track.channels,
        )
    }
}

/// Why a track was chosen.
public enum TrackChoiceReason: Hashable, Sendable {
    /// The user picked it for this item.
    case item
    /// Remembered from another episode of the season.
    case season
    /// Remembered from another episode of the series.
    case series
    /// The language and subtitle settings.
    case preferences
}

/// The track to play, `nil` for none, and why.
public struct TrackChoiceResult: Hashable, Sendable {
    public let track: MediaTrack?
    public let reason: TrackChoiceReason

    public init(_ track: MediaTrack?, _ reason: TrackChoiceReason) {
        self.track = track
        self.reason = reason
    }
}
