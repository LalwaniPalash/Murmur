import Foundation
import MurmurMLXProtocol
import Testing
@testable import MurmurNext

struct MLXWorkerClientTests {
    @Test func workerFailureIsContentFreeAndRecoverable() async throws {
        let worker = try #require(workerExecutableURL())
        let client = MLXWorkerClient(
            launchConfiguration: MLXWorkerLaunchConfiguration(executableURL: worker, arguments: [])
        )
        await #expect(throws: MLXWorkerClientError.workerFailed("model.unsafe-path")) {
            try await client.execute(request())
        }
    }

    @Test func childAbortCannotTerminateTheHostProcess() async {
        let client = MLXWorkerClient(
            launchConfiguration: MLXWorkerLaunchConfiguration(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "kill -ABRT $$"]
            )
        )
        await #expect(throws: MLXWorkerClientError.self) {
            try await client.execute(request())
        }
    }

    @Test func timeoutTerminatesAStuckWorker() async {
        let client = MLXWorkerClient(
            launchConfiguration: MLXWorkerLaunchConfiguration(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "sleep 10"],
                timeout: .milliseconds(40)
            )
        )
        await #expect(throws: MLXWorkerClientError.timedOut) {
            try await client.execute(request())
        }
    }

    @Test func repeatedFailuresOpenTheLaunchCircuit() async {
        let client = MLXWorkerClient(
            launchConfiguration: MLXWorkerLaunchConfiguration(
                executableURL: URL(fileURLWithPath: "/usr/bin/false"),
                arguments: []
            )
        )
        for _ in 0..<3 {
            await #expect(throws: MLXWorkerClientError.self) {
                try await client.execute(request())
            }
        }
        #expect(await client.isHealthy() == false)
        await #expect(throws: MLXWorkerClientError.workerUnhealthy) {
            try await client.execute(request())
        }
    }

    private func request() -> MLXWorkerRequest {
        MLXWorkerRequest(
            modelIdentifier: "qwen-test",
            modelDirectoryPath: "/tmp/qwen-test",
            operation: "professional-email",
            sourceText: "Hello, please review the plan.",
            spokenInstruction: nil,
            protectedTerms: [],
            outputTokenLimit: 128
        )
    }

    private func workerExecutableURL() -> URL? {
        let buildCandidate = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/arm64-apple-macosx/debug/MurmurMLXWorker")
        if FileManager.default.isExecutableFile(atPath: buildCandidate.path) { return buildCandidate }
        var directory = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = directory.appendingPathComponent("MurmurMLXWorker")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
            directory.deleteLastPathComponent()
        }
        return nil
    }
}
