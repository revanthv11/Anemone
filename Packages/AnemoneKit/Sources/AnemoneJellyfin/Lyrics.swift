import Foundation
import Get
import JellyfinAPI

/// A song's lyrics from `/Audio/{id}/Lyrics`: lines with their start times when they're synced,
/// as Wholphin's Now Playing page shows them.
public struct Lyrics: Hashable, Sendable {
    public struct Line: Hashable, Sendable {
        /// When the line starts; `nil` for lyrics without times.
        public var start: Duration?
        public var text: String

        public init(start: Duration?, text: String) {
            self.start = start
            self.text = text
        }
    }

    public var lines: [Line]
    /// Moves the lines against the song: the server's `Offset`, which Wholphin adds to the
    /// position before finding the line.
    public var offset: Duration

    public init(lines: [Line], offset: Duration = .zero) {
        self.lines = lines
        self.offset = offset
    }

    /// Whether lines have start times, so the current one can be highlighted.
    public var isSynced: Bool {
        lines.contains { $0.start != nil }
    }

    /// The line being sung at `position`: the last one that has started, as Wholphin finds it.
    /// `nil` before the first line, and for lyrics without times.
    public func lineIndex(at position: Duration) -> Int? {
        let lyricPosition = position + offset
        return lines.lastIndex { line in line.start.map { lyricPosition >= $0 } ?? false }
    }
}

public extension JellyfinSession {
    /// The song's lyrics, or `nil` when it has none.
    func lyrics(for songID: MediaItem.ID) async throws -> Lyrics? {
        do {
            let dto = try await send(Paths.getLyrics(itemID: songID))
            let lyrics = Lyrics(dto)
            return lyrics.lines.isEmpty ? nil : lyrics
        } catch APIError.unacceptableStatusCode(404) {
            return nil
        }
    }
}

extension Lyrics {
    init(_ dto: LyricDto) {
        self.init(
            lines: (dto.lyrics ?? []).map { line in
                Line(start: line.start.map(Duration.init(ticks:)), text: line.text ?? "")
            },
            offset: dto.metadata?.offset.map(Duration.init(ticks:)) ?? .zero,
        )
    }
}
