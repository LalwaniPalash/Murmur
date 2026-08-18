import Foundation
import MLXLLM
import MLXLMCommon
import MurmurMLXProtocol
import Tokenizers

private struct LocalTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let tokenizer = try await AutoTokenizer.from(modelFolder: directory)
        return TokenizerAdapter(tokenizer)
    }
}

private struct TokenizerAdapter: MLXLMCommon.Tokenizer {
    private let base: any Tokenizers.Tokenizer

    init(_ base: any Tokenizers.Tokenizer) {
        self.base = base
    }

    var bosToken: String? { base.bosToken }
    var eosToken: String? { base.eosToken }
    var unknownToken: String? { base.unknownToken }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        base.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        base.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? { base.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { base.convertIdToToken(id) }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        try base.applyChatTemplate(
            messages: messages,
            tools: tools,
            additionalContext: additionalContext
        )
    }
}

private enum WorkerFailure: String, Error {
    case unsafeModelPath = "model.unsafe-path"
    case generationFailed = "generation.failed"
}

@main
private enum MurmurMLXWorkerMain {
    private static let runtime = WorkerRuntime()

    static func main() async {
        while let line = readLine(strippingNewline: true) {
            let input = Data(line.utf8)
            let data: Data
            do {
                let request = try MLXWorkerCodec.decodeRequest(input)
                let response = try await execute(request)
                data = try JSONEncoder().encode(response)
            } catch let failure as WorkerFailure {
                data = failureResponse(input: input, code: failure.rawValue)
            } catch {
                data = failureResponse(input: input, code: WorkerFailure.generationFailed.rawValue)
            }
            guard data.isEmpty == false else { continue }
            var framed = data
            framed.append(0x0A)
            try? FileHandle.standardOutput.write(contentsOf: framed)
        }
    }

    private static func execute(_ request: MLXWorkerRequest) async throws -> MLXWorkerResponse {
        let modelDirectory = try validatedModelDirectory(request.modelDirectoryPath)
        let started = ContinuousClock.now
        let output = try await runtime.generate(
            modelDirectory: modelDirectory,
            prompt: prompt(for: request),
            outputTokenLimit: request.outputTokenLimit
        )
        return MLXWorkerResponse(
            requestID: request.requestID,
            status: "ok",
            outputText: normalizedModelOutput(output),
            modelIdentifier: request.modelIdentifier,
            elapsedMilliseconds: durationMilliseconds(started.duration(to: .now))
        )
    }

    private static func validatedModelDirectory(_ path: String) throws -> URL {
        let candidate = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        let root = applicationSupport
            .appendingPathComponent("Murmur/v2/Models/Writing", isDirectory: true)
            .standardizedFileURL
        guard candidate.deletingLastPathComponent() == root,
              candidate.resolvingSymlinksInPath() == candidate,
              (try? candidate.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]).isDirectory) == true,
              (try? candidate.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true
        else { throw WorkerFailure.unsafeModelPath }
        return candidate
    }

    private static func prompt(for request: MLXWorkerRequest) -> String {
        let instruction: String
        switch request.operation {
        case "professional-email":
            instruction = """
            Format the dictation as a professional email. Preserve every spoken word and every
            fact, address, number, date, name, commitment, negation, greeting, and sign-off.
            You may change capitalization and punctuation and add paragraph breaks. Do not add,
            remove, replace, paraphrase, or infer words. Do not add commentary.
            """
        default:
            instruction = """
            Apply the spoken instruction to the source text. Preserve facts and protected details
            unless explicitly asked to remove wording. Do not answer or comment on the instruction.
            The result must perform the instruction; when asked to make text concise, remove
            redundant wording while preserving its meaning and facts.
            Spoken instruction: \(request.spokenInstruction ?? "")
            """
        }
        return """
        /no_think
        \(instruction)
        Protected terms: \(request.protectedTerms.joined(separator: ", "))
        Return one JSON object and nothing else: {"text":"result"}.
        Source text:
        \(request.sourceText)
        """
    }

    private static func normalizedModelOutput(_ output: String) -> String {
        var result = output.replacingOccurrences(
            of: #"(?s)<think>.*?</think>\s*"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("```"), result.hasSuffix("```") {
            result.removeFirst(3)
            result.removeLast(3)
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.lowercased().hasPrefix("json") {
                result.removeFirst(4)
                result = result.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return result
    }

    private static func durationMilliseconds(_ duration: Duration) -> Int {
        let components = duration.components
        let value = components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000
        return max(0, Int(clamping: value))
    }

    private static func failureResponse(input: Data, code: String) -> Data {
        guard let request = try? MLXWorkerCodec.decodeRequest(input),
              let data = try? JSONEncoder().encode(MLXWorkerResponse(
                requestID: request.requestID,
                status: "failed",
                failureCode: code
              ))
        else {
            return Data()
        }
        return data
    }
}

private actor WorkerRuntime {
    private var loadedModelPath: String?
    private var container: ModelContainer?

    func generate(
        modelDirectory: URL,
        prompt: String,
        outputTokenLimit: Int
    ) async throws -> String {
        let path = modelDirectory.path
        let active: ModelContainer
        if loadedModelPath == path, let container {
            active = container
        } else {
            let loaded = try await LLMModelFactory.shared.loadContainer(
                from: modelDirectory,
                using: LocalTokenizerLoader()
            )
            loadedModelPath = path
            container = loaded
            active = loaded
        }
        let parameters = GenerateParameters(
            maxTokens: outputTokenLimit,
            temperature: 0,
            repetitionPenalty: 1.08,
            repetitionContextSize: 64
        )
        let session = ChatSession(active, generateParameters: parameters)
        return try await session.respond(to: prompt)
    }
}
