import Foundation

struct OpenAITextTransformationEngine: WritingTextTransformationEngine {
    private static let maximumSourceCharacters = 40_000
    private static let maximumRequestBytes = 128 * 1_024
    private static let maximumResponseBytes = 256 * 1_024
    private static let maximumOutputTokens = 2_000

    private let baseURL: URL?
    private let acceptedRoute: WritingTransformationRoute
    private let credentials: any ProviderCredentialProviding
    private let transport: any TransformationHTTPTransport

    init(
        baseURL: URL? = URL(string: "https://api.openai.com/v1")!,
        acceptedRoute: WritingTransformationRoute = .openAI,
        credentials: any ProviderCredentialProviding = ProviderCredentialStore.shared,
        transport: any TransformationHTTPTransport = URLSessionTransformationHTTPTransport()
    ) {
        self.baseURL = baseURL
        self.acceptedRoute = acceptedRoute
        self.credentials = credentials
        self.transport = transport
    }

    func transform(_ request: WritingTransformationRequest) async throws -> WritingTransformationResponse {
        do {
            try validate(request)
            guard let configuredBaseURL = baseURL ?? request.policy.endpoint else {
                throw TransformationProviderFailure.invalidRequest
            }
            let base = try TransformationEndpointPolicy.validate(configuredBaseURL.absoluteString)
            let endpoint = try TransformationEndpointPolicy.endpoint(base: base, route: "responses")
            let provider = request.policy.providerIdentifier ?? "openai"
            let credential: String
            do {
                credential = try await credentials.credential(providerIdentifier: provider)
            } catch {
                throw TransformationProviderFailure.missingCredential
            }

            let body = try makeBody(request)
            guard body.count <= Self.maximumRequestBytes else {
                throw TransformationProviderFailure.invalidRequest
            }
            var urlRequest = URLRequest(url: endpoint)
            urlRequest.httpMethod = "POST"
            urlRequest.timeoutInterval = request.policy.timeoutSeconds
            urlRequest.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
            urlRequest.httpBody = body

            let response = try await transport.send(
                urlRequest,
                maximumResponseBytes: Self.maximumResponseBytes
            )
            guard response.data.count <= Self.maximumResponseBytes else {
                throw TransformationProviderFailure.oversizedResponse
            }
            try validate(statusCode: response.statusCode)
            return try parse(response.data, request: request)
        } catch let failure as TransformationProviderFailure {
            throw failure
        } catch is CancellationError {
            throw TransformationProviderFailure.cancelled
        } catch let error as URLError {
            switch error.code {
            case .timedOut: throw TransformationProviderFailure.timeout
            case .cancelled: throw TransformationProviderFailure.cancelled
            default: throw TransformationProviderFailure.networkUnavailable
            }
        } catch {
            throw TransformationProviderFailure.malformedResponse
        }
    }

    private func validate(_ request: WritingTransformationRequest) throws {
        let source = request.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard request.policy.shouldTransform,
              request.policy.route == acceptedRoute,
              request.policy.operation == request.operation,
              request.policy.providerIdentifier == expectedProviderIdentifier,
              request.policy.modelIdentifier?.isEmpty == false,
              request.policy.timeoutSeconds > 0,
              source.isEmpty == false,
              source.count <= Self.maximumSourceCharacters
        else { throw TransformationProviderFailure.invalidRequest }

        switch request.operation {
        case .professionalEmail:
            let required: Set<WritingOutboundDataCategory> = [
                .completedTranscript, .writingInstruction, .applicationCategory,
            ]
            guard request.policy.allowedOutboundData == required,
                  request.spokenInstruction == nil
            else { throw TransformationProviderFailure.invalidRequest }
        case .semanticCommand:
            let required: Set<WritingOutboundDataCategory> = [
                .selectedText, .spokenInstruction, .writingInstruction, .applicationCategory,
            ]
            guard request.policy.allowedOutboundData == required,
                  request.spokenInstruction?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            else { throw TransformationProviderFailure.invalidRequest }
        }
    }

    private var expectedProviderIdentifier: String {
        acceptedRoute == .openAICompatible ? "openai-compatible" : "openai"
    }

    private func makeBody(_ request: WritingTransformationRequest) throws -> Data {
        var userPayload: [String: Any] = [
            "operation": request.operation.rawValue,
            "application_category": request.applicationCategory,
            request.operation == .professionalEmail ? "completed_transcript" : "selected_text": request.sourceText,
        ]
        if let spokenInstruction = request.spokenInstruction {
            userPayload["spoken_instruction"] = spokenInstruction
        }
        let userData = try JSONSerialization.data(withJSONObject: userPayload, options: [.sortedKeys])
        let userText = String(decoding: userData, as: UTF8.self)

        let body: [String: Any] = [
            "model": request.policy.modelIdentifier!,
            "store": false,
            "max_output_tokens": Self.maximumOutputTokens,
            "reasoning": ["effort": "none"],
            "input": [
                ["role": "system", "content": instruction(for: request.operation)],
                ["role": "user", "content": userText],
            ],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "murmur_transformation",
                    "strict": true,
                    "schema": [
                        "type": "object",
                        "properties": [
                            "text": ["type": "string", "maxLength": Self.maximumSourceCharacters],
                        ],
                        "required": ["text"],
                        "additionalProperties": false,
                    ],
                ],
            ],
        ]
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    private func instruction(for operation: WritingTransformationOperation) -> String {
        switch operation {
        case .professionalEmail:
            "Rewrite the supplied dictated text as a clear, professional email. Preserve every fact, name, address, URL, number, date, commitment, greeting, and sign-off exactly. Add paragraph breaks where the topic or intent changes. Do not invent a greeting, sign-off, recipient, fact, or commitment. Return only the required JSON object."
        case .semanticCommand:
            "Apply the supplied spoken instruction to the selected text. Preserve every fact, name, address, URL, number, date, identifier, and commitment unless the instruction explicitly requests its removal. Return only the required JSON object."
        }
    }

    private func validate(statusCode: Int) throws {
        switch statusCode {
        case 200 ..< 300: return
        case 401, 403: throw TransformationProviderFailure.authentication
        case 408: throw TransformationProviderFailure.timeout
        case 429: throw TransformationProviderFailure.rateLimited
        case 500 ... 599: throw TransformationProviderFailure.server(statusCode)
        default: throw TransformationProviderFailure.malformedResponse
        }
    }

    private func parse(
        _ data: Data,
        request: WritingTransformationRequest
    ) throws -> WritingTransformationResponse {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TransformationProviderFailure.malformedResponse
        }
        guard root["status"] as? String == "completed" else {
            throw TransformationProviderFailure.incomplete
        }
        guard let output = root["output"] as? [[String: Any]] else {
            throw TransformationProviderFailure.malformedResponse
        }

        var structuredText: String?
        for item in output where item["type"] as? String == "message" {
            guard let content = item["content"] as? [[String: Any]] else { continue }
            for part in content {
                if part["type"] as? String == "refusal" {
                    throw TransformationProviderFailure.refused
                }
                if part["type"] as? String == "output_text", let text = part["text"] as? String {
                    structuredText = text
                }
            }
        }
        guard let structuredText,
              let structuredData = structuredText.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: structuredData) as? [String: Any],
              let text = object["text"] as? String,
              Set(object.keys) == ["text"],
              text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              text.count <= Self.maximumSourceCharacters
        else { throw TransformationProviderFailure.malformedResponse }

        let usage: WritingTransformationUsage?
        if let rawUsage = root["usage"] as? [String: Any] {
            usage = WritingTransformationUsage(
                inputTokens: rawUsage["input_tokens"] as? Int,
                outputTokens: rawUsage["output_tokens"] as? Int
            )
        } else {
            usage = nil
        }
        return WritingTransformationResponse(
            text: text,
            providerIdentifier: request.policy.providerIdentifier ?? "openai",
            modelIdentifier: root["model"] as? String ?? request.policy.modelIdentifier!,
            usage: usage
        )
    }
}
