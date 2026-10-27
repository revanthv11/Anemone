import JellyfinAPI

/// What choosing between AVPlayer and MPV needs to know about an item's video.
public struct ItemVideo: Hashable, Sendable {
    /// HDR10, HDR10+, HLG or Dolby Vision.
    public var isHDR: Bool
    /// Wider than 2560 or taller than 1440: Wholphin's test, since 4K films are often less than
    /// 2160 lines tall.
    public var is4K: Bool

    public init(isHDR: Bool, is4K: Bool) {
        self.isHDR = isHDR
        self.is4K = is4K
    }
}

public extension JellyfinSession {
    /// The video of the item's version `mediaSourceID`, or of its first, from `/Items/{id}`,
    /// which sends the versions and their streams. `nil` when the item has no video.
    func itemVideo(of itemID: MediaItem.ID, mediaSourceID: String? = nil) async throws -> ItemVideo? {
        let item = try await send(Paths.getItem(itemID: itemID, userID: userID))
        let sources = item.mediaSources ?? []
        let source = sources.first { $0.id == mediaSourceID } ?? sources.first
        return source?.mediaStreams?.first { $0.type == .video }.map(ItemVideo.init)
    }
}

extension ItemVideo {
    /// Wholphin's `isHdr` and `is4k` in `PlaybackViewModel.play`.
    init(_ stream: MediaStream) {
        let range = stream.videoRangeType ?? .unknown
        isHDR = stream.videoRange == .hdr || (range != .sdr && range != .unknown)
        is4K = (stream.width ?? 0) > 2560 || (stream.height ?? 0) > 1440
    }
}
