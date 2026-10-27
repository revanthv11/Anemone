import AnemonePlayback
import Synchronization

/// The slideshow's waits, which end when the test calls `elapse()` rather than when their time
/// is up; one cancelled ends at once, as `Task.sleep` does. Tests check which wait is under way
/// instead of sleeping and hoping the machine kept up.
final class ManualSleeps: Sendable {
    private struct Wait {
        let id: Int
        let length: Duration
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var started = 0
        var waits: [Wait] = []
    }

    private let state = Mutex(State())

    /// How many waits have started.
    var started: Int {
        state.withLock(\.started)
    }

    /// The lengths of the waits not yet over, oldest first.
    var pending: [Duration] {
        state.withLock { $0.waits.map(\.length) }
    }

    var sleep: Slideshow.Sleep {
        { [self] length in try await wait(length) }
    }

    /// Ends the oldest wait, as if its time had passed.
    func elapse() {
        let wait = state.withLock { $0.waits.isEmpty ? nil : $0.waits.removeFirst() }
        wait?.continuation.resume()
    }

    private func wait(_ length: Duration) async throws {
        let id = state.withLock { state in
            defer { state.started += 1 }
            return state.started
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.withLock { $0.waits.append(Wait(id: id, length: length, continuation: continuation)) }
                // Cancelled before it was added: the handler found nothing to end.
                if Task.isCancelled {
                    end(id)
                }
            }
        } onCancel: {
            end(id)
        }
    }

    private func end(_ id: Int) {
        let wait = state.withLock { state in
            state.waits.firstIndex { $0.id == id }.map { state.waits.remove(at: $0) }
        }
        wait?.continuation.resume(throwing: CancellationError())
    }
}
