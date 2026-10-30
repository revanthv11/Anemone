import SwiftUI

/// The time of day, "9:41 PM", moving on at each minute, as the screensaver and the player's
/// overlay show it; each sets its own font and colour.
public struct ClockText: View {
    public init() {}

    public var body: some View {
        TimelineView(.everyMinute) { context in
            Text(context.date, format: .dateTime.hour().minute())
        }
        .monospacedDigit()
    }
}
