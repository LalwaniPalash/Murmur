import Foundation

protocol DictationAudioRetentionSession: AnyObject, Sendable {
    func enqueue(_ samples: [Float])
    func seal()
    func discard()
}

final class BackgroundAudioRetentionSession: DictationAudioRetentionSession, @unchecked Sendable {
    private let lock = NSLock()
    private let continuation: AsyncStream<[Float]>.Continuation
    private let worker: Task<Void, Never>
    private let coordinator: RetentionCoordinator
    private let sessionID: UUID
    private var terminalActionTaken = false

    init(
        coordinator: RetentionCoordinator,
        sessionID: UUID,
        policy: AudioRetentionPolicy,
        sampleRate: Int,
        createdAt: Date,
        errorHandler: @escaping @Sendable (String) -> Void,
        completionHandler: @escaping @Sendable (UUID) -> Void = { _ in }
    ) {
        self.coordinator = coordinator
        self.sessionID = sessionID
        let (stream, continuation) = AsyncStream<[Float]>.makeStream(
            bufferingPolicy: .unbounded
        )
        self.continuation = continuation
        worker = Task(priority: .utility) {
            do {
                guard try await coordinator.begin(
                    sessionID: sessionID,
                    policy: policy,
                    sampleRate: sampleRate,
                    createdAt: createdAt
                ) != nil else { return }
                for await samples in stream {
                    guard Task.isCancelled == false else { break }
                    try await coordinator.append(samples, sessionID: sessionID)
                }
                if Task.isCancelled {
                    try await coordinator.cancel(sessionID: sessionID, deleteCiphertext: true)
                } else {
                    _ = try await coordinator.finalize(sessionID: sessionID)
                    completionHandler(sessionID)
                }
            } catch is CancellationError {
                try? await coordinator.cancel(sessionID: sessionID, deleteCiphertext: true)
            } catch {
                try? await coordinator.cancel(sessionID: sessionID, deleteCiphertext: true)
                errorHandler(error.localizedDescription)
            }
        }
    }

    func enqueue(_ samples: [Float]) {
        lock.lock()
        let isOpen = terminalActionTaken == false
        lock.unlock()
        if isOpen, samples.isEmpty == false { continuation.yield(samples) }
    }

    func seal() {
        lock.lock()
        guard terminalActionTaken == false else {
            lock.unlock()
            return
        }
        terminalActionTaken = true
        lock.unlock()
        continuation.finish()
    }

    func discard() {
        lock.lock()
        guard terminalActionTaken == false else {
            lock.unlock()
            return
        }
        terminalActionTaken = true
        lock.unlock()
        worker.cancel()
        continuation.finish()
    }
}
