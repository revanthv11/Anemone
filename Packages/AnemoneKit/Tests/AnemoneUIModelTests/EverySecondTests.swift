import AnemoneUI
import Foundation
import SwiftUI
import Testing

/// The schedule the player's "Ends at" is worked out again on.
struct EverySecondTests {
    @Test func `every second counts from one moment, however often it's asked for`() async throws {
        let from = Date.now
        let first = Array(PeriodicTimelineSchedule.everySecond.entries(from: from, mode: .normal).prefix(3))

        // As a view's body asks for it again on a later run.
        try await Task.sleep(for: .milliseconds(20))
        let again = Array(PeriodicTimelineSchedule.everySecond.entries(from: from, mode: .normal).prefix(3))

        #expect(first.count == 3)
        #expect(first == again)
        #expect(zip(first, first.dropFirst()).allSatisfy { $1.timeIntervalSince($0) == 1 })
    }
}
