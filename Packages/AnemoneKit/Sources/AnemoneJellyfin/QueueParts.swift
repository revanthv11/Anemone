import Foundation
import JellyfinAPI

/// Where a queue starts: an item, and which of its places when it's listed more than once, as a
/// playlist can list the same item twice.
public struct QueueStart: Equatable, Sendable {
    public let itemID: MediaItem.ID
    /// How many places earlier list the same item.
    public let occurrence: Int

    /// The video entry at or after `index` in `entries`, a page's listing that may hold entries
    /// the video player leaves out, such as songs. `nil` when no video comes after it.
    public init?(at index: Int, in entries: [ItemDetails]) {
        guard entries.indices.contains(index),
              let video = entries[index...].firstIndex(where: { PlayableItems.videoKinds.contains($0.item.kind) })
        else { return nil }
        let id = entries[video].id
        itemID = id
        occurrence = entries[..<video].count { $0.id == id }
    }

    /// Its place in `items`, the queue's videos in the same order. `nil` when it isn't there,
    /// as when the entry can't be played any more.
    public func index(in items: [ItemDetails]) -> Int? {
        let places = items.indices.filter { items[$0].id == itemID }
        return places.indices.contains(occurrence) ? places[occurrence] : nil
    }
}

/// A video split across files plays its other parts after it, as Wholphin's `PlaylistCreator`
/// adds them to every queue.
public extension JellyfinSession {
    /// A video's additional parts, for one split across files (`PartCount` above 1): what
    /// `/Videos/{id}/AdditionalParts` lists, in order, to play after it. Nothing, and no request,
    /// for a video in one file. Wholphin's `convertAndAddParts` adds them to every queue.
    func additionalParts(of video: ItemDetails) async throws -> [ItemDetails] {
        guard (video.item.partCount ?? 1) > 1 else { return [] }
        return try await send(Paths.getAdditionalPart(itemID: video.id, userID: userID)).items.available
    }

    /// `items` with each video's additional parts after it, as Wholphin's `convertAndAddParts`
    /// builds a queue. Only videos with parts are asked about, all at once. A video whose parts
    /// can't be read plays alone, rather than the whole queue failing over one of its videos.
    func addingParts(to items: [ItemDetails]) async -> [ItemDetails] {
        let split = items.indices.filter { (items[$0].item.partCount ?? 1) > 1 }
        guard !split.isEmpty else { return items }
        let parts = await withTaskGroup(of: (Int, [ItemDetails]).self) { group in
            for index in split {
                let video = items[index]
                group.addTask { await (index, (try? self.additionalParts(of: video)) ?? []) }
            }
            var found: [Int: [ItemDetails]] = [:]
            for await (index, videoParts) in group {
                found[index] = videoParts
            }
            return found
        }
        return items.indices.flatMap { [items[$0]] + (parts[$0] ?? []) }
    }
}
