import AnemoneCore
import Foundation
import JellyfinAPI

/// Subtitles the server sends beside a stream as a file of their own, for a player that fetches
/// them itself, as MPV does.
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
    /// The subtitles PlaybackInfo delivers as External with `stream`: files beside the video,
    /// ones downloaded on an earlier play among them, and in a transcode, text subtitles from the
    /// file, which the stream can't carry. Each comes with where a player fetches it, built as
    /// PlaybackInfo's `DeliveryUrl` is, since `PlaybackStream` keeps the delivery but not the URL:
    /// in its own format when the player's profile lists it in `formats`, else as SRT, which the
    /// server converts to.
    func externalSubtitles(of stream: PlaybackStream, formats: Set<String>) -> [ExternalSubtitle] {
        let mediaSourceID = stream.mediaSourceID ?? stream.itemID
        return stream.tracks.of(.subtitle).compactMap { track in
            guard track.delivery == .external else { return nil }
            let codec = track.codec?.lowercased()
            let format = codec.flatMap { formats.contains($0) ? $0 : nil } ?? "srt"
            let request = Paths.getSubtitle(
                routeItemID: stream.itemID,
                routeMediaSourceID: mediaSourceID,
                routeIndex: track.index,
                routeFormat: format,
            )
            guard let url = client.url(with: request, queryAPIKey: true) else { return nil }
            return ExternalSubtitle(
                url: url,
                title: track.displayTitle ?? track.title ?? track.language ?? String(
                    localized: "Subtitles \(track.index)",
                    bundle: .module,
                ),
                language: track.language,
                isDefault: track.index == stream.subtitleStreamIndex,
            )
        }
    }
}
