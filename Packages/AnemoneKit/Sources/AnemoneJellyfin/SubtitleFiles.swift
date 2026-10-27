import AnemoneCore
import Foundation
import JellyfinAPI

/// A text subtitle stream as a file of its own, for Anemone to draw over the video.
public struct SubtitleFile: Hashable, Sendable {
    /// The formats Anemone reads. The server converts any text subtitle to either.
    public enum Format: String, Hashable, Sendable {
        case srt
        case vtt
    }

    public var format: Format
    public var text: String

    public init(format: Format, text: String) {
        self.format = format
        self.text = text
    }
}

/// Which subtitle file to fetch: one of a version's subtitle streams, in a format Anemone reads.
public struct SubtitleFileRequest: Hashable, Sendable {
    public var itemID: MediaItem.ID
    public var mediaSourceID: String
    /// The stream's index in the version, as PlaybackInfo numbers it.
    public var index: Int
    public var format: SubtitleFile.Format

    public init(itemID: MediaItem.ID, mediaSourceID: String, index: Int, format: SubtitleFile.Format) {
        self.itemID = itemID
        self.mediaSourceID = mediaSourceID
        self.index = index
        self.format = format
    }

    /// `track` of the item's version `mediaSourceID`: WebVTT as it is, and anything else as SRT,
    /// which the server writes from SubRip as it was and converts other text formats to.
    public init(_ track: MediaTrack, itemID: MediaItem.ID, mediaSourceID: String) {
        let isWebVTT = ["vtt", "webvtt"].contains(track.codec?.lowercased())
        self.init(itemID: itemID, mediaSourceID: mediaSourceID, index: track.index, format: isWebVTT ? .vtt : .srt)
    }
}

public extension JellyfinSession {
    /// Fetches a text subtitle stream whole, from the server's subtitle endpoint
    /// (`/Videos/{itemId}/{mediaSourceId}/Subtitles/{index}/Stream.{format}`). The server reads
    /// it out of the video file, or the file beside it, and converts it to the format asked for,
    /// with times from the start of the video. This is what Anemone draws text subtitles from,
    /// rather than the WebVTT in Jellyfin's HLS playlists, whose times AVPlayer shows 10 s late
    /// in a remuxed stream.
    func subtitleFile(_ request: SubtitleFileRequest) async throws -> SubtitleFile {
        let path = Paths.getSubtitle(
            routeItemID: request.itemID,
            routeMediaSourceID: request.mediaSourceID,
            routeIndex: request.index,
            routeFormat: request.format.rawValue,
        )
        // As data, since not every file is UTF-8.
        let data = try await send(path.withResponse(Data.self))
        return SubtitleFile(format: request.format, text: SubtitleFile.decode(data))
    }
}

extension SubtitleFile {
    /// The file's text: UTF-8 or UTF-16 as their byte-order marks say, else UTF-8, else Windows
    /// Latin-1, which older SRT files are often in and which reads any bytes.
    static func decode(_ data: Data) -> String {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let text = String(data: data, encoding: .utf16)
        {
            return text
        }
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        return String(data: data, encoding: .windowsCP1252) ?? String(bytes: data, encoding: .isoLatin1) ?? ""
    }
}
