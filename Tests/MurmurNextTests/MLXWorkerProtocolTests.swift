import Foundation
import MurmurMLXProtocol
import Testing

struct MLXWorkerProtocolTests {
    @Test func roundTripsABoundedVersionedRequest() throws {
        let request = fixture()
        #expect(try MLXWorkerCodec.decodeRequest(MLXWorkerCodec.encode(request)) == request)
    }

    @Test func rejectsOversizedSourceAndMismatchedResponseIdentity() throws {
        let oversized = fixture(source: String(repeating: "x", count: MLXWorkerProtocolLimits.maximumSourceBytes + 1))
        #expect(throws: MLXWorkerProtocolError.invalidRequest) { try MLXWorkerCodec.encode(oversized) }

        let request = fixture()
        let response = MLXWorkerResponse(requestID: UUID(), status: "ok", outputText: "Safe output")
        let data = try JSONEncoder().encode(response)
        #expect(throws: MLXWorkerProtocolError.invalidResponse) {
            try MLXWorkerCodec.decodeResponse(data, requestID: request.requestID)
        }
    }

    private func fixture(source: String = "Hello, please review the plan.") -> MLXWorkerRequest {
        MLXWorkerRequest(
            modelIdentifier: "qwen-test",
            modelDirectoryPath: "/tmp/qwen-test",
            operation: "professional-email",
            sourceText: source,
            spokenInstruction: nil,
            protectedTerms: ["Palash"],
            outputTokenLimit: 512
        )
    }
}
