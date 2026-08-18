import Foundation
import MurmurMLXProtocol
#if canImport(Darwin)
import Darwin
#endif

enum MLXWorkerClientError: Error, Equatable, Sendable {
    case workerUnavailable
    case workerCrashed(exitCode: Int32)
    case invalidResponse
    case workerFailed(String)
    case timedOut
    case cancelled
    case workerUnhealthy
}

struct MLXWorkerLaunchConfiguration: Sendable {
    let executableURL: URL
    let arguments: [String]
    let timeout: Duration

    init(executableURL: URL, arguments: [String], timeout: Duration = .seconds(60)) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.timeout = timeout
    }

    static func bundled() -> MLXWorkerLaunchConfiguration? {
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/MurmurMLXWorker")
        guard FileManager.default.isExecutableFile(atPath: url.path) else { return nil }
        return MLXWorkerLaunchConfiguration(executableURL: url, arguments: [])
    }
}

actor MLXWorkerClient {
    private let launchConfiguration: MLXWorkerLaunchConfiguration?
    private var worker: ResidentWorkerProcess?
    private var consecutiveFailures = 0
    private var unhealthyForLaunch = false

    init(launchConfiguration: MLXWorkerLaunchConfiguration? = .bundled()) {
        self.launchConfiguration = launchConfiguration
    }

    deinit {
        worker?.terminate()
    }

    func execute(_ request: MLXWorkerRequest) async throws -> MLXWorkerResponse {
        guard unhealthyForLaunch == false else { throw MLXWorkerClientError.workerUnhealthy }
        guard let launchConfiguration else { throw MLXWorkerClientError.workerUnavailable }
        let input: Data
        do {
            input = try MLXWorkerCodec.encode(request)
        } catch {
            throw MLXWorkerClientError.invalidResponse
        }

        let activeWorker: ResidentWorkerProcess
        do {
            activeWorker = try ensureWorker(launchConfiguration)
            try activeWorker.writeLine(input)
        } catch {
            resetWorker()
            recordFailure()
            throw MLXWorkerClientError.workerUnavailable
        }

        let output: Data
        do {
            output = try await withTaskCancellationHandler {
                try await readResponse(
                    from: activeWorker,
                    timeout: launchConfiguration.timeout
                )
            } onCancel: {
                activeWorker.terminate()
            }
            try Task.checkCancellation()
        } catch is CancellationError {
            resetWorker()
            throw MLXWorkerClientError.cancelled
        } catch let error as MLXWorkerClientError {
            resetWorker()
            recordFailure()
            throw error
        } catch {
            resetWorker()
            recordFailure()
            throw MLXWorkerClientError.workerUnavailable
        }

        if output.isEmpty, activeWorker.process.isRunning == false {
            let status = activeWorker.process.terminationStatus
            resetWorker()
            recordFailure()
            throw MLXWorkerClientError.workerCrashed(exitCode: status)
        }

        let response: MLXWorkerResponse
        do {
            response = try MLXWorkerCodec.decodeResponse(output, requestID: request.requestID)
        } catch {
            if activeWorker.process.isRunning == false {
                let status = activeWorker.process.terminationStatus
                resetWorker()
                recordFailure()
                throw MLXWorkerClientError.workerCrashed(exitCode: status)
            }
            resetWorker()
            recordFailure()
            throw MLXWorkerClientError.invalidResponse
        }
        guard response.status == "ok" else {
            recordFailure()
            throw MLXWorkerClientError.workerFailed(response.failureCode ?? "worker.failed")
        }
        consecutiveFailures = 0
        return response
    }

    func isHealthy() -> Bool { unhealthyForLaunch == false }

    private func recordFailure() {
        consecutiveFailures += 1
        if consecutiveFailures >= 3 {
            unhealthyForLaunch = true
            resetWorker()
        }
    }

    private func ensureWorker(
        _ configuration: MLXWorkerLaunchConfiguration
    ) throws -> ResidentWorkerProcess {
        if let worker, worker.process.isRunning { return worker }
        resetWorker()
        let created = try ResidentWorkerProcess(configuration: configuration)
        worker = created
        return created
    }

    private func resetWorker() {
        worker?.terminate()
        worker = nil
    }

    private func readResponse(
        from worker: ResidentWorkerProcess,
        timeout: Duration
    ) async throws -> Data {
        try await withThrowingTaskGroup(of: WorkerReadOutcome.self) { group in
            group.addTask {
                .data(try worker.readLine(maximumBytes: MLXWorkerProtocolLimits.maximumResponseBytes))
            }
            group.addTask {
                try await ContinuousClock().sleep(for: timeout)
                worker.terminate()
                return .timedOut
            }
            let first = try await group.next() ?? .timedOut
            group.cancelAll()
            switch first {
            case .data(let data): return data
            case .timedOut: throw MLXWorkerClientError.timedOut
            }
        }
    }
}

private enum WorkerReadOutcome: Sendable {
    case data(Data)
    case timedOut
}

private final class ResidentWorkerProcess: @unchecked Sendable {
    let process: Process
    private let input: FileHandle
    private let output: FileHandle
    private let lock = NSLock()

    init(configuration: MLXWorkerLaunchConfiguration) throws {
#if canImport(Darwin)
        // A worker can die between the liveness check and a pipe write. Ignore SIGPIPE so
        // Foundation reports the broken pipe as an ordinary error instead of killing Murmur.
        signal(SIGPIPE, SIG_IGN)
#endif
        let process = Process()
        let standardInput = Pipe()
        let standardOutput = Pipe()
        process.executableURL = configuration.executableURL
        process.arguments = configuration.arguments
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        // Native diagnostics may contain model paths or fragments. The protocol carries only
        // bounded content-free failure codes back to the main app.
        process.standardError = FileHandle.nullDevice
        try process.run()
        self.process = process
        input = standardInput.fileHandleForWriting
        output = standardOutput.fileHandleForReading
    }

    func writeLine(_ data: Data) throws {
        var framed = data
        framed.append(0x0A)
        try input.write(contentsOf: framed)
    }

    func readLine(maximumBytes: Int) throws -> Data {
        var result = Data()
        while result.count <= maximumBytes {
            let chunk = output.availableData
            guard chunk.isEmpty == false else {
                return result
            }
            if let newline = chunk.firstIndex(of: 0x0A) {
                result.append(chunk[..<newline])
                return result
            }
            result.append(chunk)
        }
        throw MLXWorkerClientError.invalidResponse
    }

    func terminate() {
        lock.lock()
        defer { lock.unlock() }
        try? input.close()
        if process.isRunning { process.terminate() }
    }
}
