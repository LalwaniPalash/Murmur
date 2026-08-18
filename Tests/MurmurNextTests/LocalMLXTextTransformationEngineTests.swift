import Foundation
import Testing
@testable import MurmurNext

struct LocalMLXTextTransformationEngineTests {
    @Test func packagedRunnerFailsClosedWhenWorkerIsUnavailable() async {
        let runner = MLXLocalWritingModelRunner()
        await #expect(throws: LocalWritingModelFailure.generationFailed) {
            try await runner.generate(
                LocalWritingModelRunRequest(
                    modelDirectory: URL(fileURLWithPath: "/tmp/unused-local-model"),
                    prompt: "Return deterministic fallback.",
                    outputTokenLimit: 16
                )
            )
        }
    }

    @Test func transformsProfessionalEmailWithThePinnedLocalModelAndBoundedGeneration() async throws {
        let runner = RecordingLocalWritingModelRunner(result: #"{"text":"Hello Palash,\n\nPlease review the plan.\n\nBest,\nSam"}"#)
        let locator = StubLocalWritingModelLocator()
        let engine = LocalMLXTextTransformationEngine(runner: runner, modelLocator: locator)
        let request = localRequest(
            source: "hello Palash please review the plan best Sam",
            operation: .professionalEmail
        )

        let response = try await engine.transform(request)
        let captured = try #require(await runner.lastRequest())

        #expect(response.text == "Hello Palash,\n\nPlease review the plan.\n\nBest, Sam")
        #expect(response.providerIdentifier == "local-mlx")
        #expect(response.modelIdentifier == LocalWritingModelManifest.qwen3_0_6B_4Bit.id)
        #expect(response.usage == nil)
        #expect(captured.modelDirectory == locator.directory)
        #expect(captured.outputTokenLimit == 512)
        #expect(captured.prompt.contains(request.sourceText))
        #expect(captured.prompt.contains(request.applicationCategory))
        #expect(captured.prompt.contains("Return one JSON object"))
        #expect(captured.prompt.utf8.count <= 131_072)
    }

    @Test func commandUsesOnlySelectedTextAndSpokenInstruction() async throws {
        let runner = RecordingLocalWritingModelRunner(result: #"{"text":"Ship Friday."}"#)
        let engine = LocalMLXTextTransformationEngine(
            runner: runner,
            modelLocator: StubLocalWritingModelLocator()
        )
        let request = localRequest(
            source: "I think we should probably ship Friday.",
            instruction: "Make it concise",
            operation: .semanticCommand
        )

        _ = try await engine.transform(request)
        let prompt = try #require(await runner.lastRequest()?.prompt)

        #expect(prompt.contains(request.sourceText))
        #expect(prompt.contains(request.spokenInstruction!))
        #expect(prompt.contains("clipboard") == false)
        #expect(prompt.contains("browser URL") == false)
        #expect(prompt.contains("history") == false)
    }

    @Test func rejectsWrongRouteMissingModelMalformedAndOversizedOutput() async {
        let validLocator = StubLocalWritingModelLocator()
        let wrongRoute = localRequest(source: "Hello", operation: .professionalEmail, route: .openAI)
        let validRunner = RecordingLocalWritingModelRunner(result: #"{"text":"Hello."}"#)
        let engine = LocalMLXTextTransformationEngine(runner: validRunner, modelLocator: validLocator)
        await #expect(throws: LocalWritingModelFailure.invalidRequest) {
            try await engine.transform(wrongRoute)
        }

        let missing = LocalMLXTextTransformationEngine(
            runner: validRunner,
            modelLocator: StubLocalWritingModelLocator(error: .modelUnavailable)
        )
        await #expect(throws: LocalWritingModelFailure.modelUnavailable) {
            try await missing.transform(localRequest(source: "Hello", operation: .professionalEmail))
        }

        let malformed = LocalMLXTextTransformationEngine(
            runner: RecordingLocalWritingModelRunner(result: "not json"),
            modelLocator: validLocator
        )
        await #expect(throws: LocalWritingModelFailure.malformedResponse) {
            try await malformed.transform(localRequest(source: "Hello", operation: .professionalEmail))
        }

        let oversized = LocalMLXTextTransformationEngine(
            runner: RecordingLocalWritingModelRunner(result: String(repeating: "x", count: 262_145)),
            modelLocator: validLocator
        )
        await #expect(throws: LocalWritingModelFailure.oversizedResponse) {
            try await oversized.transform(localRequest(source: "Hello", operation: .professionalEmail))
        }
    }

    @Test func cancellationStopsBeforePublishingModelOutput() async {
        let runner = SuspendingLocalWritingModelRunner()
        let engine = LocalMLXTextTransformationEngine(
            runner: runner,
            modelLocator: StubLocalWritingModelLocator()
        )
        let task = Task {
            try await engine.transform(localRequest(source: "Hello", operation: .professionalEmail))
        }

        await runner.waitUntilStarted()
        task.cancel()

        await #expect(throws: LocalWritingModelFailure.cancelled) {
            try await task.value
        }
    }

    @Test func successfulEmailGetsDeterministicParagraphsButCommandDoesNot() async throws {
        let singleParagraph = "Respected sir, I hope this email finds you well. Please grant an extension. Thank you. Regards."
        let runner = RecordingLocalWritingModelRunner(result: #"{"text":"\#(singleParagraph)"}"#)
        let engine = LocalMLXTextTransformationEngine(
            runner: runner,
            modelLocator: StubLocalWritingModelLocator()
        )

        let email = try await engine.transform(localRequest(
            source: singleParagraph,
            operation: .professionalEmail
        ))
        let command = try await engine.transform(localRequest(
            source: singleParagraph,
            instruction: "Keep this exact text",
            operation: .semanticCommand
        ))

        #expect(email.text.contains("\n\n"))
        #expect(command.text == singleParagraph)
    }
}

private func localRequest(
    source: String,
    instruction: String? = nil,
    operation: WritingTransformationOperation,
    route: WritingTransformationRoute = .localMLX
) -> WritingTransformationRequest {
    WritingTransformationRequest(
        sourceText: source,
        spokenInstruction: instruction,
        operation: operation,
        applicationCategory: operation == .professionalEmail ? "email" : "document",
        policy: CapturedWritingPolicy(
            route: route,
            operation: operation,
            providerIdentifier: route == .localMLX ? "local-mlx" : "openai",
            modelIdentifier: route == .localMLX
                ? LocalWritingModelManifest.qwen3_0_6B_4Bit.id
                : WritingSettings.defaultOpenAIModelIdentifier,
            instructionVersion: operation == .professionalEmail
                ? "professional-email-v1"
                : "semantic-command-v1",
            allowedOutboundData: [],
            timeoutSeconds: 15,
            fallback: .deterministicSource,
            disableReason: nil
        )
    )
}

private struct StubLocalWritingModelLocator: LocalWritingModelLocating {
    let directory = URL(fileURLWithPath: "/tmp/murmur-local-model", isDirectory: true)
    var error: LocalWritingModelFailure?

    func verifiedModelDirectory(identifier: String) throws -> URL {
        if let error { throw error }
        guard identifier == LocalWritingModelManifest.qwen3_0_6B_4Bit.id else {
            throw LocalWritingModelFailure.modelUnavailable
        }
        return directory
    }
}

private actor RecordingLocalWritingModelRunner: LocalWritingModelRunning {
    private let result: String
    private var request: LocalWritingModelRunRequest?

    init(result: String) {
        self.result = result
    }

    func generate(_ request: LocalWritingModelRunRequest) async throws -> String {
        self.request = request
        return result
    }

    func lastRequest() -> LocalWritingModelRunRequest? {
        request
    }
}

private actor SuspendingLocalWritingModelRunner: LocalWritingModelRunning {
    private var started = false

    func generate(_ request: LocalWritingModelRunRequest) async throws -> String {
        started = true
        while Task.isCancelled == false {
            await Task.yield()
        }
        throw CancellationError()
    }

    func waitUntilStarted() async {
        while started == false {
            await Task.yield()
        }
    }
}
