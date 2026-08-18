import Foundation

/// Runs submitted operations strictly one at a time, in submission order.
///
/// Actor isolation on its own does not provide this. An actor method that suspends at an
/// `await` releases the actor, so two callers can interleave inside what looks like a
/// single critical section — which is unsafe when the work guards a resource that must
/// never be entered twice, such as a `whisper_context`.
///
/// Each submission chains onto its predecessor. The chain tail is published synchronously
/// before the first suspension point, so a caller arriving later always observes it and
/// queues behind rather than racing past.
actor SerialOperationQueue {
    private var tail: Task<Void, Never>?

    /// Submits `operation`, resuming it only once every previously submitted operation
    /// has finished.
    ///
    /// How the predecessor finished — success, failure, or cancellation — never affects
    /// the successor. Cancelling one operation must not poison the ones queued behind it,
    /// which is what makes "cancel the stale work, immediately start its replacement"
    /// safe for callers.
    func run<Value: Sendable>(
        _ operation: @Sendable @escaping () async throws -> Value
    ) async throws -> Value {
        let predecessor = tail
        let task = Task<Value, Error> {
            if let predecessor { await predecessor.value }
            return try await operation()
        }
        tail = Task { _ = try? await task.value }
        return try await task.value
    }
}
