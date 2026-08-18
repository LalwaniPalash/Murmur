import Foundation
import MurmurMLXProtocol
import MurmurQualityCore
import Testing
@testable import MurmurNext

struct LocalMLXRealModelIntegrationTests {
    @Test func residentWorkerReusesTheLoadedPinnedModel() async throws {
        guard ProcessInfo.processInfo.environment["MURMUR_RUN_LOCAL_WRITING_MODEL_TESTS"] == "1" else {
            return
        }
        let model = LocalWritingModelManifest.qwen3_0_6B_4Bit
        let directory = try LocalWritingModelCatalog().verifiedModelDirectory(identifier: model.id)
        let worker = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/arm64-apple-macosx/debug/MurmurMLXWorker")
        let client = MLXWorkerClient(launchConfiguration: .init(
            executableURL: worker,
            arguments: [],
            timeout: .seconds(60)
        ))
        func request(_ id: UUID) -> MLXWorkerRequest {
            .init(
                requestID: id,
                modelIdentifier: model.id,
                modelDirectoryPath: directory.path,
                operation: "semantic-command",
                sourceText: "The project is currently in a state where it is not yet complete.",
                spokenInstruction: "Rewrite this using fewer words",
                protectedTerms: [],
                outputTokenLimit: 96
            )
        }
        let first = try await client.execute(request(UUID()))
        let second = try await client.execute(request(UUID()))
        #expect(first.outputText?.contains("\"text\"") == true)
        #expect(second.outputText?.contains("\"text\"") == true)
        #expect((second.outputText?.count ?? .max) < 72)
        #expect((second.elapsedMilliseconds ?? .max) < (first.elapsedMilliseconds ?? 0))
    }

    @Test func installedPinnedModelProducesAValidatedEmailWithinTheOptInHarness() async throws {
        guard ProcessInfo.processInfo.environment["MURMUR_RUN_LOCAL_WRITING_MODEL_TESTS"] == "1" else {
            return
        }

        let source = "Hello Palash please review invoice 4821 by Friday August 7 thank you Sam"
        let request = WritingTransformationRequest(
            sourceText: source,
            spokenInstruction: nil,
            operation: .professionalEmail,
            applicationCategory: "email",
            policy: CapturedWritingPolicy(
                route: .localMLX,
                operation: .professionalEmail,
                providerIdentifier: "local-mlx",
                modelIdentifier: LocalWritingModelManifest.qwen3_0_6B_4Bit.id,
                instructionVersion: "professional-email-v1",
                allowedOutboundData: [],
                timeoutSeconds: 15,
                fallback: .deterministicSource,
                disableReason: nil
            )
        )
        let clock = ContinuousClock()
        let started = clock.now
        let worker = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/arm64-apple-macosx/debug/MurmurMLXWorker")
        let runner = MLXLocalWritingModelRunner(client: MLXWorkerClient(
            launchConfiguration: .init(executableURL: worker, arguments: [], timeout: .seconds(60))
        ))
        let response = try await LocalMLXTextTransformationEngine(runner: runner).transform(request)
        let elapsed = started.duration(to: clock.now)
        let validation = TransformationValidator().validate(
            candidate: response.text,
            source: source,
            operation: .professionalEmail
        )

        print(
            "Local MLX integration revision=\(LocalWritingModelManifest.qwen3_0_6B_4Bit.revision) " +
                "hardware=\(BenchmarkEnvironment.hardwareIdentifier) " +
                "latency_ms=\(BenchmarkEnvironment.milliseconds(elapsed)) " +
                "validation=\(validation.isValid) output=\(response.text)"
        )
        #expect(validation.isValid)
    }
}
