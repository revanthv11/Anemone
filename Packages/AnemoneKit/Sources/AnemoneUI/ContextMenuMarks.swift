import Observation

/// Marks changed from card menus, so every card of that item shows the change at once, the way
/// Wholphin refreshes the row after a menu action. The pages holding the cards keep their own
/// copies of the item, which catch up when they reload.
///
/// Changes are kept by item and show on every card of it, whatever marks the card was given: a
/// home row's card knows only the progress, an item page's knows the rest too. A card shows the
/// change while it still has a mark that a change replaced. Once its page reloads with a mark no
/// change has seen, the card's own marks are newer and win.
@MainActor
@Observable
public final class CardMarksStore {
    private var changes: [String: ItemMarkChanges] = [:]

    public init() {}

    /// What a card of the item shows, given the marks its caller passed.
    public func marks(for id: String, given marks: CardMarks) -> CardMarks {
        changes[id]?.marks(given: marks) ?? marks
    }

    /// The item's marks as the server gave them after the last change, while the card's own are
    /// older. They're complete even for a card that shows only progress. `nil` when no menu has
    /// changed the item, or the card has caught up or moved on since.
    public func savedMarks(for id: String, given marks: CardMarks) -> CardMarks? {
        changes[id]?.savedMarks(given: marks)
    }

    /// Notes that a menu changed an item's marks from `before`, the marks its card was given, to
    /// `after`, the server's answer.
    public func record(_ after: CardMarks, for id: String, replacing before: CardMarks) {
        var item = changes[id] ?? ItemMarkChanges(latest: after)
        item.record(after, replacing: before)
        changes[id] = item
    }
}

/// One item's changes: the marks the last change left, and for each mark, the values changes
/// replaced. A card that shows one of those is out of date; a card that shows a value no change
/// has seen got it from its page after the change.
struct ItemMarkChanges: Sendable {
    private(set) var latest: CardMarks
    private var favorite = ReplacedValues<Bool>()
    private var played = ReplacedValues<Bool>()
    private var unplayedCount = ReplacedValues<Int>()
    private var progress = ReplacedValues<Double>()

    init(latest: CardMarks) {
        self.latest = latest
    }

    mutating func record(_ after: CardMarks, replacing before: CardMarks) {
        favorite.record([before.badges.isFavorite, latest.badges.isFavorite], now: after.badges.isFavorite)
        played.record([before.badges.isPlayed, latest.badges.isPlayed], now: after.badges.isPlayed)
        unplayedCount.record(
            [before.badges.unplayedCount, latest.badges.unplayedCount],
            now: after.badges.unplayedCount,
        )
        progress.record([Self.progress(before), Self.progress(latest)], now: Self.progress(after))
        latest = after
    }

    /// The card's marks, with what changes changed taken from the latest when the card is out of
    /// date. Marks no change touched stay the card's own, so a home card doesn't gain a heart it
    /// never shows just because the item's page knows it's a favourite.
    func marks(given: CardMarks) -> CardMarks {
        guard isOutOfDate(given) else { return given }
        var marks = given
        if favorite.isTracked {
            marks.badges.isFavorite = latest.badges.isFavorite
        }
        if played.isTracked {
            marks.badges.isPlayed = latest.badges.isPlayed
        }
        // Only on cards that show a count, and only when the server said what it is now.
        if unplayedCount.isTracked, given.badges.unplayedCount != nil, let count = latest.badges.unplayedCount {
            marks.badges.unplayedCount = count
        }
        if progress.isTracked {
            marks.progress = latest.progress
        }
        return marks
    }

    func savedMarks(given: CardMarks) -> CardMarks? {
        isOutOfDate(given) ? latest : nil
    }

    /// Whether the card shows a value a change replaced, and none that no change has seen.
    private func isOutOfDate(_ given: CardMarks) -> Bool {
        let ages = [
            favorite.age(of: given.badges.isFavorite, latest: latest.badges.isFavorite),
            played.age(of: given.badges.isPlayed, latest: latest.badges.isPlayed),
            unplayedCount.age(of: given.badges.unplayedCount, latest: latest.badges.unplayedCount),
            progress.age(of: Self.progress(given), latest: Self.progress(latest)),
        ]
        return ages.contains(.replaced) && !ages.contains(.unseen)
    }

    /// No progress and none to show are the same to a card.
    private static func progress(_ marks: CardMarks) -> Double {
        max(marks.progress ?? 0, 0)
    }
}

/// How a card's value of a mark compares with the changes to it.
private enum MarkAge {
    /// The value the last change left.
    case latest
    /// A value a change replaced.
    case replaced
    /// A value no change has seen, so newer than the changes.
    case unseen
}

/// The values of one mark that changes replaced.
private struct ReplacedValues<Value: Hashable & Sendable>: Sendable {
    private var values: Set<Value> = []

    /// Whether a change has changed this mark.
    var isTracked: Bool {
        !values.isEmpty
    }

    mutating func record(_ old: [Value?], now new: Value?) {
        values.formUnion(old.compactMap(\.self))
        if let new {
            values.remove(new)
        }
    }

    /// How a card's value compares with the changes; `nil` when no change changed this mark, or
    /// the card doesn't show it.
    func age(of value: Value?, latest: Value?) -> MarkAge? {
        guard isTracked, let value else { return nil }
        if value == latest {
            return .latest
        }
        return values.contains(value) ? .replaced : .unseen
    }
}
