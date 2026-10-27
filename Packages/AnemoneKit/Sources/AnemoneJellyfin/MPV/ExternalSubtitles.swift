import Foundation

/// A subtitle file beside an item's video, such as one downloaded on an earlier play, for a
/// player that fetches subtitles itself, as MPV does.
public struct ExternalSubtitle: Hashable, Sendable {
    public var url: URL
    public var title: String
    /// A three-letter code such as `eng`, when the server knows it.
    public var language: String?
    /// The subtitles the server chose for the stream, which show at once.
    public var isDefault: Bool

    public init(url: URL, title: String, language: String? = nil, isDefault: Bool = false) {
        self.url = url
        self.title = title
        self.language = language
        self.isDefault = isDefault
    }
}

public extension JellyfinSession {
    /// The subtitle files beside the video of `stream`'s version that are in one of `formats`
    /// (codecs such as `subrip` or `ass`), with where a player fetches each: what PlaybackInfo
    /// delivers as External for a profile that lists those formats so. Read from `/Items/{id}`,
    /// with each file's URL built as PlaybackInfo's `DeliveryUrl` is, since `PlaybackStream`
    /// doesn't carry the source's streams. A live stream has none.
    func externalSubtitles(for stream: PlaybackStream, formats: Set<String>) async throws -> [ExternalSubtitle] {
        guard stream.liveStreamID == nil else { return [] }
        let mediaSourceID = stream.mediaSourceID ?? stream.itemID
        let subtitles = try await subtitleStreams(of: stream.itemID, mediaSourceID: mediaSourceID)
        return subtitles.compactMap { subtitle in
            guard subtitle.isExternal, let codec = subtitle.codec, formats.contains(codec.lowercased()),
                  let url = subtitleURL(for: subtitle, of: stream.itemID, mediaSourceID: mediaSourceID)
            else { return nil }
            return ExternalSubtitle(
                url: url,
                title: subtitle.title,
                language: subtitle.language,
                isDefault: subtitle.index == stream.subtitleStreamIndex,
            )
        }
    }
}
