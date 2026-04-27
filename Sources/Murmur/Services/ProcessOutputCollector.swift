import Foundation

/// Thread-safe collector for process stdout and stderr.
/// Marked @unchecked Sendable because thread safety is enforced manually via NSLock.
/// All access to stdout and stderr mutable state (storeStdout, storeStderr, combinedOutput) is protected by the lock,
/// enabling safe concurrent reads from multiple DispatchQueue.global readers during process execution.
final class ProcessOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()

    func storeStdout(_ data: Data) {
        lock.withLock {
            stdout = data
        }
    }

    func storeStderr(_ data: Data) {
        lock.withLock {
            stderr = data
        }
    }

    func combinedOutput(limit: Int = 128 * 1024) -> String {
        let data = lock.withLock { stdout + stderr }
        return String(decoding: Data(data.suffix(limit)), as: UTF8.self)
    }

    func stdoutText(limit: Int = 128 * 1024) -> String {
        let data = lock.withLock { stdout }
        return String(decoding: Data(data.suffix(limit)), as: UTF8.self)
    }

    func stderrText(limit: Int = 16 * 1024) -> String {
        let data = lock.withLock { stderr }
        return String(decoding: Data(data.suffix(limit)), as: UTF8.self)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
