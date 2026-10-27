import Foundation
import JellyfinAPI

/// A stretch of an item the server marked as an intro, credits, recap, preview or commercial,
/// which the player can offer to skip. Servers get them from plugins, such as Intro Skipper or
/// one that names segments after chapters.
public struct MediaSegment: Hashable, Identifiable, Sendable {
    /// Jellyfin's segment types, without Unknown, which Wholphin never offers to skip.
    public enum Kind: String, CaseIterable, Hashable, Sendable {
        case intro
        /// The credits.
        case outro
        case recap
        case preview
        case commercial
    }

    public let id: String
    public let kind: Kind
    public let start: Duration
    /// Just past the segment: a position here is outside it.
    public let end: Duration

    public init(id: String, kind: Kind, start: Duration, end: Duration) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
    }

    public func contains(_ position: Duration) -> Bool {
        position >= start && position < end
    }
}

public extension JellyfinSession {
    /// The item's segments in the order they play. Segments of an unknown type, or without a
    /// sensible start and end, are left out.
    func mediaSegments(for itemID: MediaItem.ID) async throws -> [MediaSegment] {
        let result = try await send(Paths.getItemSegments(itemID: itemID))
        return MediaSegment.playable(result.items ?? [], of: itemID)
    }
}

extension MediaSegment {
    /// Checked as Swiftfin's `MediaSegment` checks them: the item's own, of a known type, ending
    /// after they start, in order of start, each once.
    static func playable(_ segments: [MediaSegmentDto], of itemID: MediaItem.ID) -> [MediaSegment] {
        var ids: Set<String> = []
        return segments
            .compactMap { MediaSegment($0, of: itemID) }
            .sorted { ($0.start, $0.end) < ($1.start, $1.end) }
            .filter { ids.insert($0.id).inserted }
    }

    init?(_ segment: MediaSegmentDto, of itemID: MediaItem.ID) {
        guard segment.itemID.map({ Self.sameID($0, itemID) }) ?? true,
              let kind = segment.type.flatMap(Kind.init),
              let start = segment.startTicks, let end = segment.endTicks,
              start >= 0, end > start
        else { return nil }
        self.init(
            id: segment.id ?? "\(kind.rawValue):\(start):\(end)",
            kind: kind,
            start: Duration(ticks: start),
            end: Duration(ticks: end),
        )
    }

    /// Jellyfin writes IDs without dashes, but compares them as GUIDs, as Wholphin does.
    private static func sameID(_ first: String, _ second: String) -> Bool {
        first.replacing("-", with: "").lowercased() == second.replacing("-", with: "").lowercased()
    }
}

private extension MediaSegment.Kind {
    init?(_ type: MediaSegmentType) {
        switch type {
        case .intro: self = .intro
        case .outro: self = .outro
        case .recap: self = .recap
        case .preview: self = .preview
        case .commercial: self = .commercial
        case .unknown: return nil
        }
    }
}
