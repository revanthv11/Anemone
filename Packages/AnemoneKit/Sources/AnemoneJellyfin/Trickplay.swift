import Foundation
import JellyfinAPI

/// A video's trickplay thumbnails: small frames taken every `interval`, packed `columns` × `rows`
/// to a sheet, which the server sends as a JPEG from `/Videos/{id}/Trickplay/{width}/{index}.jpg`.
/// The player shows the frame for where the user is seeking. Ported from Wholphin's
/// `TrickplayPreview` and `SeekPreviewImage`.
public struct Trickplay: Hashable, Sendable {
    /// Where one thumbnail sits: its sheet, and its cell in the sheet, counted from the top left.
    public struct Tile: Hashable, Sendable {
        public let sheet: Int
        public let column: Int
        public let row: Int

        public init(sheet: Int, column: Int, row: Int) {
            self.sheet = sheet
            self.column = column
            self.row = row
        }
    }

    public let itemID: MediaItem.ID
    /// The version the thumbnails were taken from.
    public let mediaSourceID: String?
    /// One thumbnail's size in pixels.
    public let width: Int
    public let height: Int
    public let columns: Int
    public let rows: Int
    public let thumbnailCount: Int
    public let interval: Duration

    public init(
        itemID: MediaItem.ID,
        mediaSourceID: String?,
        width: Int,
        height: Int,
        columns: Int,
        rows: Int,
        thumbnailCount: Int,
        interval: Duration,
    ) {
        self.itemID = itemID
        self.mediaSourceID = mediaSourceID
        self.width = width
        self.height = height
        self.columns = columns
        self.rows = rows
        self.thumbnailCount = thumbnailCount
        self.interval = interval
    }

    public var thumbnailsPerSheet: Int {
        columns * rows
    }

    /// How many sheets the server has.
    public var sheetCount: Int {
        (thumbnailCount + thumbnailsPerSheet - 1) / thumbnailsPerSheet
    }

    /// The thumbnail for `position`: one per interval, as Wholphin counts them. Past the last
    /// thumbnail it's the last, where Wholphin would ask for a sheet that doesn't exist.
    public func tile(at position: Duration) -> Tile {
        let index = min(max(Int(position / interval), 0), thumbnailCount - 1)
        let cell = index % thumbnailsPerSheet
        return Tile(sheet: index / thumbnailsPerSheet, column: cell % columns, row: cell / columns)
    }
}

extension Trickplay {
    /// The preview is shown about this wide, so wider thumbnails would only cost bandwidth.
    static let preferredWidth = 480

    /// Picks from an item's trickplay manifest, which lists thumbnails by version and then by
    /// width: the playing version's (any version's when it's unknown or has none), at the widest
    /// width up to `preferredWidth`, else the narrowest. Wholphin takes the version's first width.
    init?(itemID: MediaItem.ID, manifest: [String: [String: TrickplayInfoDto]]?, mediaSourceID: String?) {
        guard let manifest, !manifest.isEmpty else { return nil }
        let sourceID = mediaSourceID.flatMap { manifest[$0] == nil ? nil : $0 }
            ?? manifest.keys.sorted().first { !(manifest[$0] ?? [:]).isEmpty }
        guard let sourceID, let widths = manifest[sourceID] else { return nil }
        let candidates = widths.values.compactMap { info -> Self? in
            guard let width = info.width, let height = info.height, let columns = info.tileWidth,
                  let rows = info.tileHeight, let count = info.thumbnailCount, let interval = info.interval,
                  width > 0, height > 0, columns > 0, rows > 0, count > 0, interval > 0
            else { return nil }
            return Self(
                itemID: itemID,
                mediaSourceID: sourceID,
                width: width,
                height: height,
                columns: columns,
                rows: rows,
                thumbnailCount: count,
                interval: .milliseconds(interval),
            )
        }
        let fitting = candidates.filter { $0.width <= Self.preferredWidth }
        guard let chosen = fitting.max(by: { $0.width < $1.width }) ?? candidates.min(by: { $0.width < $1.width })
        else { return nil }
        self = chosen
    }
}

/// What the player shows while seeking: the chapters, and trickplay thumbnails if the server
/// made them.
public struct SeekPreviews: Hashable, Sendable {
    public var chapters: [Chapter]
    public var trickplay: Trickplay?

    public init(chapters: [Chapter] = [], trickplay: Trickplay? = nil) {
        self.chapters = chapters
        self.trickplay = trickplay
    }
}

public extension JellyfinSession {
    /// An item's chapters and trickplay thumbnails for the version `mediaSourceID`, in one small
    /// request: `/Items` with just those fields, rather than everything `/Items/{id}` sends.
    func seekPreviews(for itemID: MediaItem.ID, mediaSourceID: String?) async throws -> SeekPreviews {
        let parameters = Paths.GetItemsParameters(userID: userID, fields: [.chapters, .trickplay], ids: [itemID])
        guard let dto = try await send(Paths.getItems(parameters: parameters)).items?.first else {
            throw SessionError.unexpectedResponse
        }
        return SeekPreviews(
            chapters: Chapter.chapters(dto.chapters),
            trickplay: Trickplay(itemID: itemID, manifest: dto.trickplay, mediaSourceID: mediaSourceID),
        )
    }

    /// One sheet of trickplay thumbnails, as JPEG data. Unlike item images it needs the token, so
    /// it comes through the session with the authorization header rather than as an image URL.
    func trickplaySheet(_ index: Int, of trickplay: Trickplay) async throws -> Data {
        try await send(
            Paths.getTrickplayTileImage(
                itemID: trickplay.itemID,
                width: trickplay.width,
                index: index,
                mediaSourceID: trickplay.mediaSourceID,
            ),
        )
    }
}
