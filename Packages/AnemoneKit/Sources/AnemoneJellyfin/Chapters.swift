import Foundation
import JellyfinAPI

/// A named point in a video, such as a scene, with an image the server took there. The player's
/// chapter row jumps to them. Ported from Wholphin's `Chapter`.
public struct Chapter: Hashable, Identifiable, Sendable {
    /// The chapter's place in the server's list, which its image is fetched by.
    public let index: Int
    public let name: String?
    public let start: Duration
    /// `nil` when the server has no image for it.
    public let imageTag: String?

    public init(index: Int, name: String?, start: Duration, imageTag: String? = nil) {
        self.index = index
        self.name = name
        self.start = start
        self.imageTag = imageTag
    }

    public var id: Int {
        index
    }

    /// The server's chapters in playing order, as Wholphin sorts them. Each keeps its index, so its
    /// image still matches.
    static func chapters(_ infos: [ChapterInfo]?) -> [Self] {
        (infos ?? []).enumerated().map { index, info in
            Self(
                index: index,
                name: info.name.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 },
                start: Duration(ticks: max(info.startPositionTicks ?? 0, 0)),
                imageTag: info.imageTag,
            )
        }
        .sorted { $0.start < $1.start }
    }
}

public extension [Chapter] {
    /// Where in the list the chapter playing at `position` is: the last one starting at or before
    /// it, or the first when it's before them all. `nil` when there are no chapters. Wholphin's
    /// chapter row starts with this one in focus.
    func index(at position: Duration) -> Int? {
        guard !isEmpty else { return nil }
        return (lastIndex { $0.start <= position }) ?? startIndex
    }
}

public extension JellyfinSession {
    /// A chapter's image, scaled down to `maxWidth` pixels; `nil` when it has none. Like other item
    /// images, it needs no token.
    func chapterImageURL(_ chapter: Chapter, of itemID: MediaItem.ID, maxWidth: Int) -> URL? {
        guard let tag = chapter.imageTag else { return nil }
        let parameters = Paths.GetItemImageByIndexParameters(maxWidth: maxWidth, quality: 96, tag: tag)
        return JellyfinURLs.url(
            for: Paths.getItemImageByIndex(
                itemID: itemID,
                imageType: ImageType.chapter.rawValue,
                imageIndex: chapter.index,
                parameters: parameters,
            ),
            on: serverURL,
        )
    }
}
