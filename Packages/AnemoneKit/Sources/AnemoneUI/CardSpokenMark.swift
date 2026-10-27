import Foundation

/// A mark over a card's artwork, as VoiceOver reads it after the card's title and subtitle, so a
/// card says what it shows: "Favorite", "Watched", "3 unwatched", "45% watched".
public enum CardSpokenMark: Hashable, Sendable {
    case favorite
    case watched
    /// A series', season's or collection's unwatched episodes.
    case unwatched(count: Int)
    /// How far through a partly watched item is, as a whole percentage from 1 to 100.
    case progress(percent: Int)

    /// The marks a card draws for `marks`, in the order it draws them: the heart at the top left,
    /// the check or the count at the top right, then the progress bar along the bottom. A partly
    /// watched item has the bar instead of the check, as in Wholphin, so it reads as partly
    /// watched, not watched.
    public static func marks(for marks: CardMarks) -> [CardSpokenMark] {
        let badges = marks.badges
        let progress = marks.progress ?? 0
        var spoken: [CardSpokenMark] = []
        if badges.isFavorite {
            spoken.append(.favorite)
        }
        if badges.isPlayed, progress <= 0 {
            spoken.append(.watched)
        }
        if let count = badges.unplayedCount, count > 0 {
            spoken.append(.unwatched(count: count))
        }
        if progress > 0 {
            // A sliver of a bar still reads as started, and one past the end as the whole.
            spoken.append(.progress(percent: min(max(Int((progress * 100).rounded()), 1), 100)))
        }
        return spoken
    }

    /// What VoiceOver says for the mark.
    public var spoken: LocalizedStringResource {
        switch self {
        case .favorite:
            LocalizedStringResource("Favorite", bundle: .anemoneUI)
        case .watched:
            LocalizedStringResource("Watched", bundle: .anemoneUI)
        case let .unwatched(count):
            LocalizedStringResource("\(count) unwatched", bundle: .anemoneUI)
        case let .progress(percent):
            LocalizedStringResource("\(Double(percent) / 100, format: .percent) watched", bundle: .anemoneUI)
        }
    }
}
