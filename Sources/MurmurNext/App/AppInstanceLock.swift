import Darwin
import Foundation

enum AppInstanceLockError: Error, LocalizedError {
    case openFailed(Int32)
    case lockFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .openFailed(let code): "Murmur could not open its capture lock (\(code))."
        case .lockFailed(let code): "Murmur could not acquire its capture lock (\(code))."
        }
    }
}

final class AppInstanceLock: @unchecked Sendable {
    private let lock = NSLock()
    private let url: URL
    private var descriptor: Int32 = -1
    private(set) var isOwner = false

    init(url: URL) {
        self.url = url
    }

    func acquire() throws -> Bool {
        try lock.withLock {
            if isOwner { return true }
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            for _ in 0..<2 {
                let descriptor = Darwin.open(
                    url.path,
                    O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC,
                    S_IRUSR | S_IWUSR
                )
                if descriptor >= 0 {
                    let pid = Data("\(getpid())\n".utf8)
                    let written = pid.withUnsafeBytes { bytes in
                        Darwin.write(descriptor, bytes.baseAddress, bytes.count)
                    }
                    guard written == pid.count else {
                        let code = errno
                        Darwin.close(descriptor)
                        _ = Darwin.unlink(url.path)
                        throw AppInstanceLockError.lockFailed(code)
                    }
                    self.descriptor = descriptor
                    isOwner = true
                    return true
                }
                guard errno == EEXIST else { throw AppInstanceLockError.openFailed(errno) }
                guard Self.ownerIsAlive(at: url) == false else { return false }
                // A crashed process can leave its marker. Unlinking and retrying O_EXCL is
                // race-safe: only one contender can create the replacement.
                guard Darwin.unlink(url.path) == 0 || errno == ENOENT else {
                    throw AppInstanceLockError.lockFailed(errno)
                }
            }
            return false
        }
    }

    func release() {
        lock.withLock {
            guard descriptor >= 0 else { return }
            Darwin.close(descriptor)
            _ = Darwin.unlink(url.path)
            descriptor = -1
            isOwner = false
        }
    }

    deinit { release() }

    private static func ownerIsAlive(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8),
              let ownerPID = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              ownerPID > 1
        else { return false }
        if Darwin.kill(ownerPID, 0) == 0 { return true }
        return errno == EPERM
    }
}
