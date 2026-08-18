import Foundation
import Testing
@testable import MurmurNext

struct WritingTransformationRouterTests {
    @Test func acceptedEmailUsesTheSelectedRouteAndRecordsContentFreeProvenance() async throws {
        let openAI = RouterEngine(result: .success("Hello Palash,\n\nPlease review invoice 4821."))
        let local = RouterEngine(result: .failure(LocalWritingModelFailure.generationFailed))
        let router = WritingTransformationRouter(
            openAIEngine: openAI,
            compatibleEngine: nil,
            localEngine: local
        )
        let request = routerRequest(
            source: "Hello Palash please review invoice 4821",
            operation: .professionalEmail,
            route: .openAI
        )

        let result = try await router.transform(request)
        let provenance = try #require(result.provenance)

        #expect(result.status == .applied)
        #expect(result.outputText == "Hello Palash,\n\nPlease review invoice 4821.")
        #expect(result.notice == nil)
        #expect(await openAI.requestCount == 1)
        #expect(await local.requestCount == 0)
        #expect(provenance.operation == .professionalEmail)
        #expect(provenance.route == .openAI)
        #expect(provenance.providerIdentifier == "test-provider")
        #expect(provenance.modelIdentifier == "test-model")
        #expect(provenance.instructionVersion == "professional-email-v1")
        #expect(provenance.sourceLength == request.sourceText.count)
        #expect(provenance.outputLength == result.outputText?.count)
        #expect(provenance.sourceSHA256.count == 64)
        #expect(provenance.outputSHA256.count == 64)
        #expect(provenance.validation == .accepted)
        #expect(provenance.failureCode == nil)
        #expect(provenance.duration >= 0)
    }

    @Test func invalidCandidateFallsBackToCompleteEmailSourceWithoutLeakingTheDetail() async throws {
        let source = "Email Palash at palash@example.com about invoice 4821."
        let router = WritingTransformationRouter(
            openAIEngine: RouterEngine(result: .success("Email Palash about the invoice.")),
            compatibleEngine: nil,
            localEngine: RouterEngine(result: .success("unused"))
        )

        let result = try await router.transform(routerRequest(
            source: source,
            operation: .professionalEmail,
            route: .openAI
        ))
        let provenance = try #require(result.provenance)

        #expect(result.status == .fallback)
        #expect(result.outputText == source)
        #expect(result.notice == "Used complete original")
        #expect(provenance.validation == .rejected)
        #expect(provenance.failureCode == "validation.protected-detail-missing")
        #expect(provenance.failureCode?.contains("palash@example.com") == false)
        #expect(provenance.outputSHA256 == provenance.sourceSHA256)
    }

    @Test func providerFailureFallsBackForEmailButLeavesCommandSelectionUntouched() async throws {
        let failing = RouterEngine(result: .failure(TransformationProviderFailure.authentication))
        let router = WritingTransformationRouter(
            openAIEngine: failing,
            compatibleEngine: nil,
            localEngine: failing
        )
        let email = try await router.transform(routerRequest(
            source: "Hello Palash",
            operation: .professionalEmail,
            route: .openAI
        ))
        let command = try await router.transform(routerRequest(
            source: "I think this is useful.",
            instruction: "Make it concise",
            operation: .semanticCommand,
            route: .openAI
        ))

        #expect(email.outputText == "Hello Palash")
        #expect(email.notice == "Used complete original")
        #expect(command.outputText == nil)
        #expect(command.notice == "Kept selection")
        #expect(email.provenance?.failureCode == "provider.authentication")
        #expect(command.provenance?.failureCode == "provider.authentication")
    }

    @Test func localRouteUsesOnlyTheLocalEngine() async throws {
        let openAI = RouterEngine(result: .failure(TransformationProviderFailure.authentication))
        let local = RouterEngine(result: .success("This is useful."))
        let router = WritingTransformationRouter(
            openAIEngine: openAI,
            compatibleEngine: nil,
            localEngine: local
        )

        let result = try await router.transform(routerRequest(
            source: "I think this is useful.",
            instruction: "Make it concise",
            operation: .semanticCommand,
            route: .localMLX
        ))

        #expect(result.outputText == "This is useful.")
        #expect(await local.requestCount == 1)
        #expect(await openAI.requestCount == 0)
    }

    @Test func localPreferredRetriesOneStrongerModelAfterValidationRejects() async throws {
        let source = "Email Palash at palash@example.com about invoice 4821."
        let local = SequentialRouterEngine(outputs: [
            "Email Palash about the invoice.",
            "Email Palash at palash@example.com about invoice 4821.",
        ])
        let router = WritingTransformationRouter(
            openAIEngine: local,
            compatibleEngine: nil,
            localEngine: local
        )
        var request = routerRequest(source: source, operation: .professionalEmail, route: .localMLX)
        request = WritingTransformationRequest(
            sourceText: request.sourceText,
            spokenInstruction: request.spokenInstruction,
            operation: request.operation,
            applicationCategory: request.applicationCategory,
            policy: CapturedWritingPolicy(
                route: .localMLX,
                operation: .professionalEmail,
                providerIdentifier: "local-mlx",
                modelIdentifier: LocalWritingModelManifest.llama3_2_1B_4Bit.id,
                instructionVersion: "professional-email-v1",
                allowedOutboundData: [],
                timeoutSeconds: 15,
                fallback: .deterministicSource,
                disableReason: nil,
                localSelectionReason: "preferred",
                retryModelIdentifier: LocalWritingModelManifest.qwen3_1_7B_4Bit.id
            )
        )

        let result = try await router.transform(request)

        #expect(result.status == .applied)
        #expect(await local.requestCount == 2)
        #expect(result.provenance?.modelIdentifier == LocalWritingModelManifest.qwen3_1_7B_4Bit.id)
        #expect(result.provenance?.retryAttempted == true)
        #expect(result.provenance?.selectionReason == "preferred")
    }

    @Test func deterministicOrDisabledPolicyNeverCallsAnEngine() async throws {
        let engine = RouterEngine(result: .success("unexpected"))
        let router = WritingTransformationRouter(
            openAIEngine: engine,
            compatibleEngine: nil,
            localEngine: engine
        )
        let request = routerRequest(
            source: "Hello",
            operation: .professionalEmail,
            route: .deterministic
        )

        let result = try await router.transform(request)

        #expect(result.status == .notRequested)
        #expect(result.outputText == nil)
        #expect(result.provenance == nil)
        #expect(await engine.requestCount == 0)
    }
}

private actor SequentialRouterEngine: WritingTextTransformationEngine {
    private var outputs: [String]
    private(set) var requestCount = 0

    init(outputs: [String]) { self.outputs = outputs }

    func transform(_ request: WritingTransformationRequest) async throws -> WritingTransformationResponse {
        let index = min(requestCount, outputs.count - 1)
        requestCount += 1
        return WritingTransformationResponse(
            text: outputs[index],
            providerIdentifier: "local-mlx",
            modelIdentifier: request.policy.modelIdentifier ?? "missing",
            usage: nil
        )
    }
}

private actor RouterEngine: WritingTextTransformationEngine {
    private let result: Result<String, Error>
    private(set) var requestCount = 0

    init(result: Result<String, Error>) {
        self.result = result
    }

    func transform(_ request: WritingTransformationRequest) async throws -> WritingTransformationResponse {
        requestCount += 1
        return WritingTransformationResponse(
            text: try result.get(),
            providerIdentifier: "test-provider",
            modelIdentifier: "test-model",
            usage: nil
        )
    }
}

private func routerRequest(
    source: String,
    instruction: String? = nil,
    operation: WritingTransformationOperation,
    route: WritingTransformationRoute
) -> WritingTransformationRequest {
    let provider: String?
    let model: String?
    switch route {
    case .deterministic: (provider, model) = (nil, nil)
    case .openAI: (provider, model) = ("openai", WritingSettings.defaultOpenAIModelIdentifier)
    case .openAICompatible: (provider, model) = ("openai-compatible", "test-model")
    case .localMLX: (provider, model) = ("local-mlx", LocalWritingModelManifest.qwen3_0_6B_4Bit.id)
    }
    return WritingTransformationRequest(
        sourceText: source,
        spokenInstruction: instruction,
        operation: operation,
        applicationCategory: operation == .professionalEmail ? "email" : "document",
        policy: CapturedWritingPolicy(
            route: route,
            operation: operation,
            providerIdentifier: provider,
            modelIdentifier: model,
            instructionVersion: operation == .professionalEmail
                ? "professional-email-v1"
                : "semantic-command-v1",
            allowedOutboundData: route.isRemote
                ? (operation == .professionalEmail
                    ? [.completedTranscript, .writingInstruction, .applicationCategory]
                    : [.selectedText, .spokenInstruction, .writingInstruction, .applicationCategory])
                : [],
            timeoutSeconds: route.isRemote ? 8 : 15,
            fallback: .deterministicSource,
            disableReason: route == .deterministic ? .deterministicRoute : nil
        )
    )
}
