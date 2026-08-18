import Foundation
import Testing
@testable import MurmurNext

struct OpenAITextTransformationEngineTests {
    @Test func sendsOnlyCapturedTextScopeWithStructuredOutputAndNoStorage() async throws {
        let source = "Hi Ananya, send the update to owner@example.com by August 12, 2026. Thanks, Palash."
        let transformed = "Hi Ananya,\n\nPlease send the update to owner@example.com by August 12, 2026.\n\nThanks,\nPalash"
        let transport = TestTransformationHTTPTransport(
            outcome: .response(status: 200, data: responseData(text: transformed))
        )
        let engine = OpenAITextTransformationEngine(
            credentials: StaticCredentialProvider(value: "sk-test-secret"),
            transport: transport
        )

        let response = try await engine.transform(request(source: source))

        #expect(response.text == transformed)
        #expect(response.providerIdentifier == "openai")
        #expect(response.modelIdentifier == "gpt-5.6")
        let sent = try #require(await transport.lastRequest())
        #expect(sent.url?.absoluteString == "https://api.openai.com/v1/responses")
        #expect(sent.httpMethod == "POST")
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test-secret")
        #expect(sent.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try #require(sent.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "gpt-5.6")
        #expect(json["store"] as? Bool == false)
        #expect(json["max_output_tokens"] as? Int == 2_000)
        #expect(json["tools"] == nil)
        #expect(json["background"] == nil)

        let text = try #require(json["text"] as? [String: Any])
        let format = try #require(text["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        #expect(format["strict"] as? Bool == true)

        let serialized = String(decoding: body, as: UTF8.self)
        #expect(serialized.contains(source))
        #expect(serialized.contains("application_category"))
        #expect(serialized.contains("Email"))
        #expect(serialized.contains("sk-test-secret") == false)
        #expect(serialized.localizedCaseInsensitiveContains("clipboard") == false)
        #expect(serialized.localizedCaseInsensitiveContains("browser_url") == false)
        #expect(serialized.localizedCaseInsensitiveContains("history") == false)
    }

    @Test func commandRequestIncludesOnlyInstructionAndSelectedText() async throws {
        let transport = TestTransformationHTTPTransport(
            outcome: .response(status: 200, data: responseData(text: "This is useful."))
        )
        let engine = OpenAITextTransformationEngine(
            credentials: StaticCredentialProvider(value: "key"),
            transport: transport
        )

        _ = try await engine.transform(request(
            source: "I think that this is really very useful.",
            operation: .semanticCommand,
            spokenInstruction: "Make it more concise"
        ))

        let sent = try #require(await transport.lastRequest())
        let body = String(decoding: try #require(sent.httpBody), as: UTF8.self)
        #expect(body.contains("Make it more concise"))
        #expect(body.contains("I think that this is really very useful."))
        #expect(body.contains("completed_transcript") == false)
    }

    @Test func compatibleResponsesRouteUsesOnlyItsCapturedValidatedEndpoint() async throws {
        let transport = TestTransformationHTTPTransport(
            outcome: .response(status: 200, data: responseData(text: "Complete result."))
        )
        let engine = OpenAITextTransformationEngine(
            baseURL: nil,
            acceptedRoute: .openAICompatible,
            credentials: StaticCredentialProvider(value: "compatible-key"),
            transport: transport
        )
        let policy = CapturedWritingPolicy(
            route: .openAICompatible,
            operation: .professionalEmail,
            providerIdentifier: "openai-compatible",
            modelIdentifier: "writer-model",
            instructionVersion: "professional-email-v1",
            endpoint: URL(string: "https://writer.example.test/v1"),
            allowedOutboundData: [.completedTranscript, .writingInstruction, .applicationCategory],
            timeoutSeconds: 8,
            fallback: .deterministicSource,
            disableReason: nil
        )

        let response = try await engine.transform(WritingTransformationRequest(
            sourceText: "Complete result.",
            spokenInstruction: nil,
            operation: .professionalEmail,
            applicationCategory: "Email",
            policy: policy
        ))

        #expect(response.providerIdentifier == "openai-compatible")
        #expect(await transport.lastRequest()?.url?.absoluteString == "https://writer.example.test/v1/responses")
    }

    @Test(arguments: [
        (401, TransformationProviderFailure.authentication),
        (403, TransformationProviderFailure.authentication),
        (429, TransformationProviderFailure.rateLimited),
        (500, TransformationProviderFailure.server(500)),
    ])
    func mapsHTTPFailuresWithoutReturningProviderContent(
        status: Int,
        expected: TransformationProviderFailure
    ) async {
        let transport = TestTransformationHTTPTransport(
            outcome: .response(status: status, data: Data(#"{"error":{"message":"secret provider detail"}}"#.utf8))
        )
        let engine = OpenAITextTransformationEngine(
            credentials: StaticCredentialProvider(value: "key"),
            transport: transport
        )

        await #expect(throws: expected) {
            try await engine.transform(request(source: "Please send the update."))
        }
    }

    @Test func rejectsIncompleteRefusalMalformedAndOversizedResponses() async {
        let fixtures: [(Data, TransformationProviderFailure)] = [
            (Data(#"{"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"output":[]}"#.utf8), .incomplete),
            (Data(#"{"status":"completed","output":[{"type":"message","content":[{"type":"refusal","refusal":"No"}]}]}"#.utf8), .refused),
            (Data(#"{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"not json"}]}]}"#.utf8), .malformedResponse),
            (Data(repeating: 0x78, count: 262_145), .oversizedResponse),
        ]

        for (data, expected) in fixtures {
            let transport = TestTransformationHTTPTransport(outcome: .response(status: 200, data: data))
            let engine = OpenAITextTransformationEngine(
                credentials: StaticCredentialProvider(value: "key"),
                transport: transport
            )
            await #expect(throws: expected) {
                try await engine.transform(request(source: "Please send the update."))
            }
        }
    }

    @Test(arguments: [
        (TestHTTPFailure.timeout, TransformationProviderFailure.timeout),
        (TestHTTPFailure.cancelled, TransformationProviderFailure.cancelled),
        (TestHTTPFailure.offline, TransformationProviderFailure.networkUnavailable),
    ])
    func mapsTransportFailures(error: TestHTTPFailure, expected: TransformationProviderFailure) async {
        let transport = TestTransformationHTTPTransport(outcome: .failure(error))
        let engine = OpenAITextTransformationEngine(
            credentials: StaticCredentialProvider(value: "key"),
            transport: transport
        )
        await #expect(throws: expected) {
            try await engine.transform(request(source: "Please send the update."))
        }
    }

    private func request(
        source: String,
        operation: WritingTransformationOperation = .professionalEmail,
        spokenInstruction: String? = nil
    ) -> WritingTransformationRequest {
        WritingTransformationRequest(
            sourceText: source,
            spokenInstruction: spokenInstruction,
            operation: operation,
            applicationCategory: "Email",
            policy: CapturedWritingPolicy(
                route: .openAI,
                operation: operation,
                providerIdentifier: "openai",
                modelIdentifier: "gpt-5.6",
                instructionVersion: operation == .professionalEmail ? "professional-email-v1" : "semantic-command-v1",
                allowedOutboundData: operation == .professionalEmail
                    ? [.completedTranscript, .writingInstruction, .applicationCategory]
                    : [.selectedText, .spokenInstruction, .writingInstruction, .applicationCategory],
                timeoutSeconds: 8,
                fallback: .deterministicSource,
                disableReason: nil
            )
        )
    }

    private func responseData(text: String) -> Data {
        let structured = try! JSONSerialization.data(withJSONObject: ["text": text])
        let structuredText = String(decoding: structured, as: UTF8.self)
        return try! JSONSerialization.data(withJSONObject: [
            "id": "resp_test",
            "status": "completed",
            "model": "gpt-5.6",
            "output": [[
                "type": "message",
                "content": [["type": "output_text", "text": structuredText]],
            ]],
            "usage": ["input_tokens": 20, "output_tokens": 12],
        ])
    }
}

private struct StaticCredentialProvider: ProviderCredentialProviding {
    let value: String
    func credential(providerIdentifier: String) async throws -> String { value }
}

enum TestHTTPFailure: Error, Sendable {
    case timeout
    case cancelled
    case offline
}

private actor TestTransformationHTTPTransport: TransformationHTTPTransport {
    enum Outcome: Sendable {
        case response(status: Int, data: Data)
        case failure(TestHTTPFailure)
    }

    private let outcome: Outcome
    private var request: URLRequest?

    init(outcome: Outcome) { self.outcome = outcome }

    func send(_ request: URLRequest, maximumResponseBytes: Int) async throws -> TransformationHTTPResponse {
        self.request = request
        switch outcome {
        case .response(let status, let data):
            return TransformationHTTPResponse(statusCode: status, data: data)
        case .failure(let failure):
            switch failure {
            case .timeout: throw URLError(.timedOut)
            case .cancelled: throw CancellationError()
            case .offline: throw URLError(.notConnectedToInternet)
            }
        }
    }

    func lastRequest() -> URLRequest? { request }
}
