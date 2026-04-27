import Darwin
import Foundation

enum CLIProcessRunnerError: LocalizedError {
    case timedOut(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .timedOut(let description), .failed(let description):
            description
        }
    }
}

enum CLIProcessRunner {
    /// Synchronous blocking API: DispatchSemaphore and DispatchGroup are appropriate here because
    /// readDataToEndOfFile() is a blocking syscall that should not run on Swift's cooperative thread pool.
    /// Callers wrap this in Task.detached or nonisolated(nonsending) context for async compatibility.
    @discardableResult
    static func run(
        executablePath: String,
        arguments: [String],
        environment: [String: String] = [:],
        timeout: TimeInterval = 180,
        onProcess: ((Process) -> Void)? = nil
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let resolvedEnvironment = ProcessInfo.processInfo.environment
            .merging(defaultRuntimeEnvironment(for: executablePath)) { _, new in new }
            .merging(environment) { _, new in new }
        process.environment = resolvedEnvironment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            semaphore.signal()
        }

        let readGroup = DispatchGroup()
        let collector = ProcessOutputCollector()

        try process.run()
        onProcess?(process)

        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            collector.storeStdout(stdout.fileHandleForReading.readDataToEndOfFile())
            readGroup.leave()
        }

        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            collector.storeStderr(stderr.fileHandleForReading.readDataToEndOfFile())
            readGroup.leave()
        }

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if semaphore.wait(timeout: .now() + 5) == .timedOut, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                _ = semaphore.wait(timeout: .now() + 2)
            }
            _ = readGroup.wait(timeout: .now() + 2)
            throw CLIProcessRunnerError.timedOut("\(URL(fileURLWithPath: executablePath).lastPathComponent) timed out.")
        }

        readGroup.wait()
        let output = collector.combinedOutput()

        guard process.terminationStatus == 0 else {
            throw CLIProcessRunnerError.failed(output.nonEmpty ?? "\(URL(fileURLWithPath: executablePath).lastPathComponent) failed.")
        }

        return output
    }

    private static func defaultRuntimeEnvironment(for executablePath: String) -> [String: String] {
        let executableURL = URL(fileURLWithPath: executablePath)
        let libexecURL = executableURL.deletingLastPathComponent().appendingPathComponent("libexec", isDirectory: true)
        guard let backendPath = preferredGGMLBackendPath(in: libexecURL) else {
            return [:]
        }
        return ["GGML_BACKEND_PATH": backendPath]
    }

    private static func preferredGGMLBackendPath(in libexecURL: URL) -> String? {
        [
            "libggml-metal.so",
            "libggml-cpu-apple_m4.so",
            "libggml-cpu-apple_m2_m3.so",
            "libggml-cpu-apple_m1.so",
            "libggml-blas.so",
        ]
            .map { libexecURL.appendingPathComponent($0).path }
            .first { FileManager.default.fileExists(atPath: $0) }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
