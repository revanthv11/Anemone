import Foundation
import JellyfinAPI

/// Subtitles a server's subtitle provider (such as the OpenSubtitles plugin) offers for an item.
public struct RemoteSubtitle: Hashable, Sendable, Identifiable {
    /// What the server downloads it by.
    public let id: String
    public var name: String
    public var provider: String?
    /// Such as `srt` or `ass`.
    public var format: String?
    public var rating: Float?
    public var downloads: Int?
    /// Whether the provider matched the file itself, not just its title.
    public var isHashMatch: Bool
    public var isForced: Bool
    public var isHearingImpaired: Bool
    /// Machine- or AI-translated.
    public var isMachineTranslated: Bool

    public init(
        id: String,
        name: String,
        provider: String? = nil,
        format: String? = nil,
        rating: Float? = nil,
        downloads: Int? = nil,
        isHashMatch: Bool = false,
        isForced: Bool = false,
        isHearingImpaired: Bool = false,
        isMachineTranslated: Bool = false,
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.format = format
        self.rating = rating
        self.downloads = downloads
        self.isHashMatch = isHashMatch
        self.isForced = isForced
        self.isHearingImpaired = isHearingImpaired
        self.isMachineTranslated = isMachineTranslated
    }
}

/// A subtitle stream of one of an item's versions, as the server lists it.
public struct SubtitleStream: Hashable, Sendable {
    /// The stream's index in the version, which PlaybackInfo and the subtitle URL take.
    public var index: Int
    public var title: String
    /// A three-letter code, such as `eng`, when the stream says.
    public var language: String?
    /// Such as `srt`, `ass` or `pgssub`.
    public var codec: String?
    /// A file beside the video rather than inside it.
    public var isExternal: Bool
    /// Where the file is on the server, for telling a new download from what was there.
    public var path: String?

    public init(
        index: Int,
        title: String,
        language: String? = nil,
        codec: String? = nil,
        isExternal: Bool = false,
        path: String? = nil,
    ) {
        self.index = index
        self.title = title
        self.language = language
        self.codec = codec
        self.isExternal = isExternal
        self.path = path
    }
}

/// Finding and downloading subtitles through the server, ported from Wholphin's
/// `SubtitleSearchUtils` (`searchForSubtitles`, `downloadAndSwitchSubtitles`).
public extension JellyfinSession {
    /// What the server's subtitle providers have for the item in `language` (three letters,
    /// such as `eng`), best first as Wholphin sorts them: matches of the file itself, then by
    /// rating, then by downloads.
    func searchSubtitles(for itemID: MediaItem.ID, language: String) async throws -> [RemoteSubtitle] {
        let found = try await send(Paths.searchRemoteSubtitles(itemID: itemID, language: language))
        return found.compactMap(RemoteSubtitle.init).sorted { lhs, rhs in
            if lhs.isHashMatch != rhs.isHashMatch {
                return lhs.isHashMatch
            }
            if (lhs.rating ?? 0) != (rhs.rating ?? 0) {
                return (lhs.rating ?? 0) > (rhs.rating ?? 0)
            }
            return (lhs.downloads ?? 0) > (rhs.downloads ?? 0)
        }
    }

    /// Has the server download `subtitleID` and save it beside the item's file. The server then
    /// refreshes the item in the background, so the new stream shows up a moment later; see
    /// `newSubtitleStream(of:mediaSourceID:besides:)`.
    ///
    /// Fixed while porting: Wholphin passes the version's ID where the item's belongs, which
    /// only works while they're the same.
    func downloadSubtitles(_ subtitleID: String, for itemID: MediaItem.ID) async throws {
        try await send(Paths.downloadRemoteSubtitles(itemID: itemID, subtitleID: subtitleID))
    }

    /// The subtitle streams of the item's version `mediaSourceID`, or of its first.
    func subtitleStreams(of itemID: MediaItem.ID, mediaSourceID: String?) async throws -> [SubtitleStream] {
        let item = try await send(Paths.getItem(itemID: itemID, userID: userID))
        let sources = item.mediaSources ?? []
        let source = sources.first { $0.id == mediaSourceID } ?? sources.first
        return (source?.mediaStreams ?? []).filter { $0.type == .subtitle }.compactMap(SubtitleStream.init)
    }

    /// Waits for a downloaded subtitle file to show up among the version's streams: an external
    /// stream whose path wasn't among `known`. Like Wholphin, asks up to four times, 1.5 s apart,
    /// and gives up with `nil`.
    func newSubtitleStream(
        of itemID: MediaItem.ID,
        mediaSourceID: String?,
        besides known: [SubtitleStream],
        attempts: Int = 4,
        interval: Duration = .milliseconds(1500),
    ) async throws -> SubtitleStream? {
        let knownPaths = Set(known.compactMap(\.path))
        for _ in 0 ..< attempts {
            try await Task.sleep(for: interval)
            let streams = try await subtitleStreams(of: itemID, mediaSourceID: mediaSourceID)
            if let new = streams.first(where: { $0.isExternal && !knownPaths.contains($0.path ?? "") }) {
                return new
            }
        }
        return nil
    }

    /// Where a player fetches a subtitle stream as a file of its own, with the token in the
    /// query, since libmpv fetches it without the session's headers.
    func subtitleURL(for stream: SubtitleStream, of itemID: MediaItem.ID, mediaSourceID: String) -> URL? {
        let request = Paths.getSubtitle(
            routeItemID: itemID,
            routeMediaSourceID: mediaSourceID,
            routeIndex: stream.index,
            routeFormat: stream.codec ?? "srt",
        )
        return client.url(with: request, queryAPIKey: true)
    }
}

extension RemoteSubtitle {
    init?(_ info: RemoteSubtitleInfo) {
        guard let id = info.id, !id.isEmpty else { return nil }
        self.init(
            id: id,
            name: info.name ?? id,
            provider: info.providerName,
            format: info.format,
            rating: info.communityRating,
            downloads: info.downloadCount,
            isHashMatch: info.isHashMatch ?? false,
            isForced: info.isForced ?? false,
            isHearingImpaired: info.isHearingImpaired ?? false,
            isMachineTranslated: info.isMachineTranslated == true || info.isAiTranslated == true,
        )
    }
}

extension SubtitleStream {
    init?(_ stream: MediaStream) {
        guard let index = stream.index else { return nil }
        self.init(
            index: index,
            title: stream.displayTitle ?? stream.title ?? stream.language ?? "Subtitles \(index)",
            language: stream.language,
            codec: stream.codec,
            isExternal: stream.isExternal ?? false,
            path: stream.path,
        )
    }
}
