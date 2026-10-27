import Foundation
import JellyfinAPI

/// One of an item's versions, which Jellyfin calls media sources: a film kept in 4K and in
/// 1080p, say, or a director's cut beside the theatrical one. Most items have just one.
public struct MediaVersion: Hashable, Identifiable, Sendable {
    /// The version's video, as the server read it from the file.
    public struct Video: Hashable, Sendable {
        /// Such as `h264`, `hevc` or `av1`.
        public var codec: String?
        public var width: Int?
        public var height: Int?
        /// Frames per second, such as 23.976.
        public var frameRate: Float?
        public var range: VideoRangeType?
        /// The server's summary, such as "4K HEVC HDR10".
        public var title: String?

        public init(
            codec: String? = nil,
            width: Int? = nil,
            height: Int? = nil,
            frameRate: Float? = nil,
            range: VideoRangeType? = nil,
            title: String? = nil,
        ) {
            self.codec = codec
            self.width = width
            self.height = height
            self.frameRate = frameRate
            self.range = range
            self.title = title
        }
    }

    /// The media source ID that PlaybackInfo takes.
    public let id: String
    /// The server's name for it, such as "2160p" or "Director's Cut"; the file's name otherwise.
    public var name: String
    /// Bits per second.
    public var bitrate: Int?
    public var runtime: Duration?
    public var video: Video?

    public init(id: String, name: String, bitrate: Int? = nil, runtime: Duration? = nil, video: Video? = nil) {
        self.id = id
        self.name = name
        self.bitrate = bitrate
        self.runtime = runtime
        self.video = video
    }
}

public extension JellyfinSession {
    /// The item's versions in the server's order; the first is what plays unless one is picked.
    /// `/Items/{id}` sends every field, media sources included.
    func mediaVersions(of itemID: MediaItem.ID) async throws -> [MediaVersion] {
        let item = try await send(Paths.getItem(itemID: itemID, userID: userID))
        return (item.mediaSources ?? []).compactMap(MediaVersion.init)
    }
}

extension MediaVersion {
    /// Named as Wholphin's version dialog names them: the source's name, then its path, then
    /// its ID. Sources without an ID can't be asked for, so they're left out.
    init?(_ source: MediaSourceInfo) {
        guard let id = source.id, !id.isEmpty else { return nil }
        let fileName = source.path.map { URL(filePath: $0).deletingPathExtension().lastPathComponent }
        let name = [source.name, fileName].compactMap(\.self).first { !$0.isEmpty } ?? id
        let video = source.mediaStreams?.first { $0.type == .video }
        self.init(
            id: id,
            name: name,
            bitrate: source.bitrate,
            runtime: source.runTimeTicks.map(Duration.init(ticks:)),
            video: video.map(Video.init),
        )
    }
}

extension MediaVersion.Video {
    /// Wholphin's `RefreshRateService` reads `realFrameRate`; the average is the fallback.
    init(_ stream: MediaStream) {
        self.init(
            codec: stream.codec?.lowercased(),
            width: stream.width,
            height: stream.height,
            frameRate: stream.realFrameRate ?? stream.averageFrameRate,
            range: stream.videoRangeType,
            title: stream.displayTitle,
        )
    }
}

/// The version the user picked for each item, so Play keeps using it, as Wholphin remembers it
/// per user in its `ItemPlayback` table. Kept in UserDefaults, newest last, and only the latest
/// few hundred, since tvOS keeps little there.
public struct MediaVersionChoices: Sendable {
    /// The app's own choices.
    public static let standard = Self(suiteName: nil)

    static let key = "mediaVersionChoices"
    static let limit = 200

    /// `nil` for the standard defaults; tests use a suite of their own.
    private let suiteName: String?

    init(suiteName: String?) {
        self.suiteName = suiteName
    }

    /// The version picked for an item, or `nil` to play the server's first.
    public func choice(for itemID: MediaItem.ID, userID: String) -> String? {
        let prefix = Self.prefix(itemID, userID)
        return entries.last { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }

    public func choose(_ versionID: String, for itemID: MediaItem.ID, userID: String) {
        let prefix = Self.prefix(itemID, userID)
        var entries = entries.filter { !$0.hasPrefix(prefix) }
        entries.append(prefix + versionID)
        defaults.set(Array(entries.suffix(Self.limit)), forKey: Self.key)
    }

    /// Back to the server's first version, as when the picked one is gone from the server.
    public func forget(_ itemID: MediaItem.ID, userID: String) {
        let prefix = Self.prefix(itemID, userID)
        defaults.set(entries.filter { !$0.hasPrefix(prefix) }, forKey: Self.key)
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    /// Each entry is "user|item|version"; Jellyfin's IDs are hex, so they never hold a "|".
    private var entries: [String] {
        defaults.stringArray(forKey: Self.key) ?? []
    }

    private static func prefix(_ itemID: MediaItem.ID, _ userID: String) -> String {
        "\(userID)|\(itemID)|"
    }
}
