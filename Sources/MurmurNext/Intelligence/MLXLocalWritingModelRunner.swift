import Foundation
import MurmurMLXProtocol

/// Local writing always crosses a process boundary. Native MLX failures may call `abort()`,
/// so loading MLX in the main Murmur process is never safe regardless of Swift error handling.
actor MLXLocalWritingModelRunner: LocalWritingModelRunning {
    private let client: MLXWorkerClient

    init(client: MLXWorkerClient = MLXWorkerClient()) {
        self.client = client
    }

    func generate(_ request: LocalWritingModelRunRequest) async throws -> String {
        let operation = switch request.operation {
        case .professionalEmail: "professional-email"
        case .semanticCommand: "semantic-command"
        }
        let workerRequest = MLXWorkerRequest(
            modelIdentifier: request.modelIdentifier,
            modelDirectoryPath: request.modelDirectory.standardizedFileURL.path,
            operation: operation,
            sourceText: request.sourceText,
            spokenInstruction: request.spokenInstruction,
            protectedTerms: request.protectedTerms,
            outputTokenLimit: request.outputTokenLimit
        )
        do {
            let response = try await client.execute(workerRequest)
            guard let output = response.outputText, output.isEmpty == false else {
                throw LocalWritingModelFailure.malformedResponse
            }
            return output
        } catch is CancellationError {
            throw LocalWritingModelFailure.cancelled
        } catch let error as LocalWritingModelFailure {
            throw error
        } catch {
            throw LocalWritingModelFailure.generationFailed
        }
    }
}
