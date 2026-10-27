import Foundation
import SwiftUI

public extension TimelineSchedule where Self == PeriodicTimelineSchedule {
    /// Every second, counted from one fixed moment, for text that moves on with the clock, such
    /// as the player's "Ends at". `.periodic(from: .now, by: 1)` in a view's body is a new
    /// schedule each time the body runs, starting again from then.
    static var everySecond: PeriodicTimelineSchedule {
        .periodic(from: SecondTicks.start, by: 1)
    }
}

/// When the seconds of `everySecond` are counted from.
enum SecondTicks {
    static let start = Date.now
}
