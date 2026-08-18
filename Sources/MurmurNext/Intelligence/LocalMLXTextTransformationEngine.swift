import Foundation

struct LocalWritingModelRunRequest: Equatable, Sendable {
    let modelDirectory: URL
    let prompt: String
    let outputTokenLimit: Int
    let modelIdentifier: String
    let operation: WritingTransformationOperation
    let sourceText: String
    let spokenInstruction: String?
    let protectedTerms: [String]

    init(
        modelDirectory: URL,
        prompt: String,
        outputTokenLimit: Int,
        modelIdentifier: String = LocalWritingModelManifest.qwen3_0_6B_4Bit.id,
        operation: WritingTransformationOperation = .professionalEmail,
        sourceText: String = "",
        spokenInstruction: String? = nil,
        protectedTerms: [String] = []
    ) {
        self.modelDirectory = modelDirectory
        self.prompt = prompt
        self.outputTokenLimit = outputTokenLimit
        self.modelIdentifier = modelIdentifier
        self.operation = operation
        self.sourceText = sourceText
        self.spokenInstruction = spokenInstruction
        self.protectedTerms = protectedTerms
    }
}

protocol LocalWritingModelRunning: Sendable {
    func generate(_ request: LocalWritingModelRunRequest) async throws -> String
}

enum LocalWritingModelFailure: Error, Equatable, LocalizedError, Sendable {
    case invalidRequest
    case modelUnavailable
    case cancelled
    case generationFailed
    case malformedResponse
    case oversizedResponse

    var errorDescription: String? {
        switch self {
        case .invalidRequest: "The local writing request was invalid."
        case .modelUnavailable: "Install the selected local writing model before using it."
        case .cancelled: "Local writing was cancelled."
        case .generationFailed: "The local writing model could not complete the request."
        case .malformedResponse: "The local writing model returned an invalid result."
        case .oversizedResponse: "The local writing model returned too much data."
        }
    }
}

actor LocalMLXTextTransformationEngine: WritingTextTransformationEngine {
    private static let maximumSourceBytes = 65_536
    private static let maximumPromptBytes = 131_072
    private static let maximumResponseBytes = 262_144
    private static let outputTokenLimit = 512

    private let runner: any LocalWritingModelRunning
    private let modelLocator: any LocalWritingModelLocating

    init(modelLocator: any LocalWritingModelLocating = LocalWritingModelCatalog()) {
        runner = MLXLocalWritingModelRunner()
        self.modelLocator = modelLocator
    }

    init(
        runner: any LocalWritingModelRunning,
        modelLocator: any LocalWritingModelLocating = LocalWritingModelCatalog()
    ) {
        self.runner = runner
        self.modelLocator = modelLocator
    }

    func transform(_ request: WritingTransformationRequest) async throws -> WritingTransformationResponse {
        do {
            try Task.checkCancellation()
            try validate(request)
            guard let modelIdentifier = request.policy.modelIdentifier else {
                throw LocalWritingModelFailure.invalidRequest
            }
            let modelDirectory: URL
            do {
                modelDirectory = try modelLocator.verifiedModelDirectory(identifier: modelIdentifier)
            } catch {
                throw LocalWritingModelFailure.modelUnavailable
            }
            let prompt = try prompt(for: request)
            let output: String
            do {
                output = try await runner.generate(
                    LocalWritingModelRunRequest(
                        modelDirectory: modelDirectory,
                        prompt: prompt,
                        outputTokenLimit: Self.outputTokenLimit,
                        modelIdentifier: modelIdentifier,
                        operation: request.operation,
                        sourceText: request.sourceText,
                        spokenInstruction: request.spokenInstruction
                    )
                )
            } catch is CancellationError {
                throw LocalWritingModelFailure.cancelled
            } catch let error as LocalWritingModelFailure {
                throw error
            } catch {
                throw LocalWritingModelFailure.generationFailed
            }
            try Task.checkCancellation()
            let parsed = try parse(output)
            let transformed = request.operation == .professionalEmail
                ? DeterministicEmailFormatter().format(parsed)
                : parsed
            return WritingTransformationResponse(
                text: transformed,
                providerIdentifier: "local-mlx",
                modelIdentifier: modelIdentifier,
                usage: nil
            )
        } catch is CancellationError {
            throw LocalWritingModelFailure.cancelled
        }
    }

    private func validate(_ request: WritingTransformationRequest) throws {
        let policy = request.policy
        guard policy.shouldTransform,
              policy.route == .localMLX,
              policy.providerIdentifier == "local-mlx",
              policy.operation == request.operation,
              policy.allowedOutboundData.isEmpty,
              let modelIdentifier = policy.modelIdentifier,
              LocalWritingModelManifest.supported.contains(where: { $0.id == modelIdentifier }),
              request.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              request.sourceText.utf8.count <= Self.maximumSourceBytes,
              request.applicationCategory.utf8.count <= 128
        else {
            throw LocalWritingModelFailure.invalidRequest
        }

        switch request.operation {
        case .professionalEmail:
            guard request.spokenInstruction == nil else {
                throw LocalWritingModelFailure.invalidRequest
            }
        case .semanticCommand:
            guard let instruction = request.spokenInstruction,
                  instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                  instruction.utf8.count <= 4_096
            else {
                throw LocalWritingModelFailure.invalidRequest
            }
        }
    }

    private func prompt(for request: WritingTransformationRequest) throws -> String {
        struct Input: Encodable {
            let applicationCategory: String
            let sourceText: String
            let spokenInstruction: String?
        }
        let inputData = try JSONEncoder().encode(
            Input(
                applicationCategory: request.applicationCategory,
                sourceText: request.sourceText,
                spokenInstruction: request.spokenInstruction
            )
        )
        guard let input = String(data: inputData, encoding: .utf8) else {
            throw LocalWritingModelFailure.invalidRequest
        }

        let instruction: String
        switch request.operation {
        case .professionalEmail:
            instruction = """
            Format the completed dictation as a professional email. Preserve every spoken word
            and every fact, address, number, date, name, commitment, negation, greeting, and
            sign-off. You may change capitalization and punctuation and add paragraph breaks.
            Do not add, remove, replace, paraphrase, or infer words. Do not add commentary.
            """
        case .semanticCommand:
            instruction = """
            Apply the spoken instruction to the selected source text. Preserve facts and protected
            details unless the instruction explicitly asks to remove wording. Do not answer the
            instruction or add commentary.
            """
        }

        let prompt = """
        /no_think
        \(instruction)
        Return one JSON object and nothing else, with exactly this shape: {"text":"result"}.
        Input JSON:
        \(input)
        """
        guard prompt.utf8.count <= Self.maximumPromptBytes else {
            throw LocalWritingModelFailure.invalidRequest
        }
        return prompt
    }

    private func parse(_ output: String) throws -> String {
        guard output.utf8.count <= Self.maximumResponseBytes else {
            throw LocalWritingModelFailure.oversizedResponse
        }
        guard let data = output.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["text"],
              let text = object["text"] as? String,
              text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              text.utf8.count <= Self.maximumSourceBytes
        else {
            throw LocalWritingModelFailure.malformedResponse
        }
        return text
    }
}
