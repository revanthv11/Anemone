/// A subtitle file's cues in order, which answers what shows at any moment.
///
/// Looking up a moment is a binary search, so it's as quick after a seek as during playback
/// and keeps nothing from one lookup to the next. Cues may overlap, as a sign over dialogue
/// does; every cue showing at a moment is returned, oldest first.
public struct SubtitleTimeline: Hashable, Sendable {
    /// By start, keeping the file's order for cues that start together.
    public let cues: [SubtitleCue]
    /// For each cue, the latest end among it and the cues before it, so a lookup knows when no
    /// earlier cue can still be showing.
    private let reach: [Duration]

    /// Leaves out cues that end before they start or have no text.
    public init(_ cues: [SubtitleCue]) {
        let sorted = cues.enumerated()
            .filter { $0.element.end > $0.element.start && !$0.element.lines.isEmpty }
            .sorted { ($0.element.start, $0.offset) < ($1.element.start, $1.offset) }
            .map(\.element)
        var reach: [Duration] = []
        reach.reserveCapacity(sorted.count)
        for cue in sorted {
            reach.append(max(reach.last ?? cue.end, cue.end))
        }
        self.cues = sorted
        self.reach = reach
    }

    public var isEmpty: Bool {
        cues.isEmpty
    }

    /// The cues showing at `time`: those that have started and not yet ended.
    public func cues(at time: Duration) -> [SubtitleCue] {
        var showing: [SubtitleCue] = []
        var index = firstIndex(startingAfter: time) - 1
        while index >= 0, reach[index] > time {
            if cues[index].end > time {
                showing.append(cues[index])
            }
            index -= 1
        }
        return showing.reversed()
    }

    /// When what shows next changes after `time`: the next cue starts or one showing ends.
    /// `nil` once the last cue has ended.
    public func nextChange(after time: Duration) -> Duration? {
        let next = firstIndex(startingAfter: time)
        let start = next < cues.count ? cues[next].start : nil
        let end = cues(at: time).map(\.end).min()
        return [start, end].compactMap(\.self).min()
    }

    /// The first cue that starts after `time`, or `cues.count`.
    private func firstIndex(startingAfter time: Duration) -> Int {
        var low = 0
        var high = cues.count
        while low < high {
            let middle = (low + high) / 2
            if cues[middle].start <= time {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }
}
