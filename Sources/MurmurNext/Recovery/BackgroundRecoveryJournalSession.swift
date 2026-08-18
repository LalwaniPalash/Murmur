import Foundation

protocol DictationRecoveryJournalSession: AnyObject, Sendable {
    func transition(to phase: RecoveryPhase, resultID: UUID?, failureCode: String?)
    func complete()
    func cancel()
}

final class BackgroundRecoveryJournalSession: DictationRecoveryJournalSession, @unchecked Sendable {
    private enum Event: Sendable {
        case transition(RecoveryPhase, UUID?, String?)
        case clear
    }

    private let lock = NSLock()
    private let continuation: AsyncStream<Event>.Continuation
    private var isTerminal = false

    init(
        coordinator: RecoveryCoordinator,
        sessionID: UUID,
        targetApplication: String,
        targetBundleIdentifier: String?,
        retainedAudioAvailable: Bool,
        startedAt: Date,
        errorHandler: @escaping @Sendable (String) -> Void
    ) {
        let (events, continuation) = AsyncStream<Event>.makeStream(bufferingPolicy: .unbounded)
        self.continuation = continuation
        Task(priority: .utility) {
            for await event in events {
                do {
                    switch event {
                    case .transition(let phase, let resultID, let failureCode):
                        try await coordinator.record(RecoveryJournalRecord(
                            id: sessionID,
                            updatedAt: phase == .capturing ? startedAt : Date(),
                            phase: phase,
                            targetApplication: targetApplication,
                            targetBundleIdentifier: targetBundleIdentifier,
                            retainedAudioAvailable: retainedAudioAvailable,
                            resultID: resultID,
                            failureCode: failureCode
                        ))
                    case .clear:
                        try await coordinator.clear(sessionID: sessionID)
                    }
                } catch {
                    errorHandler(error.localizedDescription)
                }
            }
        }
        continuation.yield(.transition(.capturing, nil, nil))
    }

    func transition(to phase: RecoveryPhase, resultID: UUID? = nil, failureCode: String? = nil) {
        lock.lock()
        let active = isTerminal == false
        lock.unlock()
        if active { continuation.yield(.transition(phase, resultID, failureCode)) }
    }

    func complete() {
        finish(with: .clear)
    }

    func cancel() {
        finish(with: .clear)
    }

    private func finish(with event: Event) {
        lock.lock()
        guard isTerminal == false else {
            lock.unlock()
            return
        }
        isTerminal = true
        lock.unlock()
        continuation.yield(event)
        continuation.finish()
    }
}
