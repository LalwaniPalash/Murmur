import Foundation
import Testing

@testable import MurmurNext

/// Tracks whether any two operations were ever inside their critical section together.
private actor OverlapDetector {
    private var active = 0
    private(set) var maximumConcurrent = 0
    private(set) var completionOrder: [Int] = []

    func enter() { active += 1; maximumConcurrent = max(maximumConcurrent, active) }
    func leave(_ identifier: Int) { active -= 1; completionOrder.append(identifier) }
}

@Suite
struct SerialOperationQueueTests {
    /// The defect this guards against: an earlier implementation gated on "is a task
    /// currently running", which two callers could both clear after awaiting the same
    /// task, then start overlapping work. Suspension inside the operation is what exposes
    /// it, so every operation here yields while holding the resource.
    @Test func concurrentSubmissionsNeverOverlap() async throws {
        let queue = SerialOperationQueue()
        let detector = OverlapDetector()

        await withTaskGroup(of: Void.self) { group in
            for identifier in 0..<12 {
                group.addTask {
                    try? await queue.run {
                        await detector.enter()
                        // Multiple suspension points: a correct queue holds the slot
                        // across all of them, a reentrancy-prone one does not.
                        for _ in 0..<4 { await Task.yield() }
                        try? await Task.sleep(for: .milliseconds(2))
                        await detector.leave(identifier)
                    }
                }
            }
        }

        #expect(await detector.maximumConcurrent == 1)
        #expect(await detector.completionOrder.count == 12)
    }

    /// A failed operation must not poison the queue for whatever was submitted behind it.
    @Test func aFailedOperationDoesNotBlockLaterOnes() async throws {
        let queue = SerialOperationQueue()
        struct Failure: Error {}

        await #expect(throws: Failure.self) {
            try await queue.run { throw Failure() }
        }
        let value = try await queue.run { 42 }
        #expect(value == 42)
    }

    /// The Phase 2 flow is "cancel the stale pass, immediately start its replacement".
    /// An earlier implementation rethrew the predecessor's `CancellationError` to the next
    /// caller, which would have failed the replacement instead of running it.
    @Test func aCancelledSubmitterDoesNotCancelItsSuccessor() async throws {
        let queue = SerialOperationQueue()
        let started = OverlapDetector()

        let submitter = Task {
            try await queue.run {
                await started.enter()
                try await Task.sleep(for: .milliseconds(50))
                await started.leave(0)
            }
        }
        while await started.maximumConcurrent == 0 { await Task.yield() }
        submitter.cancel()
        _ = try? await submitter.value

        let successor = try await queue.run { "ran anyway" }
        #expect(successor == "ran anyway")
    }

    /// Operations run in an unstructured `Task`, so cancelling the *submitter* does not
    /// reach into the operation body. `ResidentWhisperEngine` depends on this: a
    /// `whisper_full` call already in flight can only be stopped through whisper's own
    /// `abort_callback`, which is why `cancel()` sets an abort flag instead of cancelling
    /// a task. If this ever changed to propagate, that engine path would need revisiting.
    @Test func cancellingTheSubmitterDoesNotAbortTheOperationBody() async throws {
        let queue = SerialOperationQueue()
        let completed = OverlapDetector()

        let submitter = Task {
            try await queue.run {
                await completed.enter()
                try? await Task.sleep(for: .milliseconds(30))
                await completed.leave(1)
            }
        }
        while await completed.maximumConcurrent == 0 { await Task.yield() }
        submitter.cancel()
        _ = try? await submitter.value

        // Drain the queue: the body still ran to completion despite the cancellation.
        _ = try await queue.run { }
        #expect(await completed.completionOrder == [1])
    }
}
