import CryptoKit
import Foundation

enum WritingTransformationRoutingStatus: String, Equatable, Sendable {
    case notRequested
    case applied
    case fallback
}

struct WritingTransformationRoutingResult: Equatable, Sendable {
    let status: WritingTransformationRoutingStatus
    /// The candidate to insert. A nil command output deliberately leaves the selection unchanged.
    let outputText: String?
    let notice: String?
    let provenance: WritingTransformationProvenance?

    static let notRequested = WritingTransformationRoutingResult(
        status: .notRequested,
        outputText: nil,
        notice: nil,
        provenance: nil
    )
}

protocol WritingTransformationRouting: Sendable {
    func transform(
        _ request: WritingTransformationRequest,
        protectedTerms: Set<String>
    ) async throws -> WritingTransformationRoutingResult
}

struct WritingTransformationRouter: WritingTransformationRouting, Sendable {
    private let openAIEngine: any WritingTextTransformationEngine
    private let compatibleEngine: (any WritingTextTransformationEngine)?
    private let localEngine: any WritingTextTransformationEngine
    private let validator: TransformationValidator

    init(
        openAIEngine: any WritingTextTransformationEngine,
        compatibleEngine: (any WritingTextTransformationEngine)?,
        localEngine: any WritingTextTransformationEngine,
        validator: TransformationValidator = TransformationValidator()
    ) {
        self.openAIEngine = openAIEngine
        self.compatibleEngine = compatibleEngine
        self.localEngine = localEngine
        self.validator = validator
    }

    func transform(
        _ request: WritingTransformationRequest,
        protectedTerms: Set<String> = []
    ) async throws -> WritingTransformationRoutingResult {
        guard request.policy.shouldTransform else { return .notRequested }
        let clock = ContinuousClock()
        let started = clock.now

        guard let engine = engine(for: request.policy.route) else {
            return fallback(
                request: request,
                duration: elapsed(since: started, clock: clock),
                validation: .providerFailed,
                failureCode: "route.unavailable"
            )
        }

        do {
            try Task.checkCancellation()
            let response = try await engine.transform(request)
            try Task.checkCancellation()
            let validation = validator.validate(
                candidate: response.text,
                source: request.sourceText,
                operation: request.operation,
                protectedTerms: protectedTerms
            )
            guard validation.isValid else {
                if request.policy.route == .localMLX,
                   let retryModel = request.policy.retryModelIdentifier {
                    let retryPolicy = CapturedWritingPolicy(
                        route: request.policy.route,
                        operation: request.policy.operation,
                        providerIdentifier: request.policy.providerIdentifier,
                        modelIdentifier: retryModel,
                        instructionVersion: request.policy.instructionVersion,
                        endpoint: request.policy.endpoint,
                        allowedOutboundData: request.policy.allowedOutboundData,
                        timeoutSeconds: request.policy.timeoutSeconds,
                        fallback: request.policy.fallback,
                        disableReason: request.policy.disableReason,
                        localSelectionReason: request.policy.localSelectionReason,
                        retryModelIdentifier: nil
                    )
                    let retryRequest = WritingTransformationRequest(
                        sourceText: request.sourceText,
                        spokenInstruction: request.spokenInstruction,
                        operation: request.operation,
                        applicationCategory: request.applicationCategory,
                        policy: retryPolicy
                    )
                    let retryResponse = try await engine.transform(retryRequest)
                    let retryValidation = validator.validate(
                        candidate: retryResponse.text,
                        source: request.sourceText,
                        operation: request.operation,
                        protectedTerms: protectedTerms
                    )
                    if retryValidation.isValid {
                        return WritingTransformationRoutingResult(
                            status: .applied,
                            outputText: retryResponse.text,
                            notice: nil,
                            provenance: provenance(
                                request: retryRequest,
                                providerIdentifier: retryResponse.providerIdentifier,
                                modelIdentifier: retryResponse.modelIdentifier,
                                output: retryResponse.text,
                                duration: elapsed(since: started, clock: clock),
                                validation: .accepted,
                                failureCode: nil,
                                retryAttempted: true
                            )
                        )
                    }
                }
                return fallback(
                    request: request,
                    duration: elapsed(since: started, clock: clock),
                    validation: .rejected,
                    failureCode: validation.failure.map(validationFailureCode) ?? "validation.rejected"
                )
            }

            return WritingTransformationRoutingResult(
                status: .applied,
                outputText: response.text,
                notice: nil,
                provenance: provenance(
                    request: request,
                    providerIdentifier: response.providerIdentifier,
                    modelIdentifier: response.modelIdentifier,
                    output: response.text,
                    duration: elapsed(since: started, clock: clock),
                    validation: .accepted,
                    failureCode: nil
                )
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled { throw CancellationError() }
            return fallback(
                request: request,
                duration: elapsed(since: started, clock: clock),
                validation: .providerFailed,
                failureCode: providerFailureCode(error)
            )
        }
    }

    private func engine(
        for route: WritingTransformationRoute
    ) -> (any WritingTextTransformationEngine)? {
        switch route {
        case .deterministic: nil
        case .openAI: openAIEngine
        case .openAICompatible: compatibleEngine
        case .localMLX: localEngine
        }
    }

    private func fallback(
        request: WritingTransformationRequest,
        duration: TimeInterval,
        validation: TransformationProvenanceValidation,
        failureCode: String
    ) -> WritingTransformationRoutingResult {
        let outputText: String?
        let notice: String
        switch request.operation {
        case .professionalEmail:
            outputText = request.sourceText
            notice = "Used complete original"
        case .semanticCommand:
            outputText = nil
            notice = "Kept selection"
        }
        return WritingTransformationRoutingResult(
            status: .fallback,
            outputText: outputText,
            notice: notice,
            provenance: provenance(
                request: request,
                providerIdentifier: request.policy.providerIdentifier,
                modelIdentifier: request.policy.modelIdentifier,
                output: request.sourceText,
                duration: duration,
                validation: validation,
                failureCode: failureCode
            )
        )
    }

    private func provenance(
        request: WritingTransformationRequest,
        providerIdentifier: String?,
        modelIdentifier: String?,
        output: String,
        duration: TimeInterval,
        validation: TransformationProvenanceValidation,
        failureCode: String?,
        retryAttempted: Bool = false
    ) -> WritingTransformationProvenance {
        WritingTransformationProvenance(
            operation: request.operation,
            route: request.policy.route,
            providerIdentifier: providerIdentifier,
            modelIdentifier: modelIdentifier,
            instructionVersion: request.policy.instructionVersion,
            sourceSHA256: Self.sha256(request.sourceText),
            sourceLength: request.sourceText.count,
            outputSHA256: Self.sha256(output),
            outputLength: output.count,
            duration: max(0, duration.isFinite ? duration : 0),
            validation: validation,
            failureCode: failureCode,
            selectionReason: request.policy.localSelectionReason,
            retryAttempted: retryAttempted,
            workerHealth: request.policy.route == .localMLX ? "available" : nil
        )
    }

    private func elapsed(since start: ContinuousClock.Instant, clock: ContinuousClock) -> TimeInterval {
        start.duration(to: clock.now).murmurMilliseconds / 1_000
    }

    private func validationFailureCode(_ failure: TransformationValidationFailure) -> String {
        switch failure {
        case .empty: "validation.empty"
        case .oversized: "validation.oversized"
        case .instructionLeakage: "validation.instruction-leakage"
        case .implausibleLength: "validation.implausible-length"
        case .protectedDetailMissing: "validation.protected-detail-missing"
        case .protectedDetailInvented: "validation.protected-detail-invented"
        }
    }

    private func providerFailureCode(_ error: Error) -> String {
        if let failure = error as? TransformationProviderFailure {
            switch failure {
            case .invalidRequest: return "provider.invalid-request"
            case .missingCredential: return "provider.missing-credential"
            case .authentication: return "provider.authentication"
            case .rateLimited: return "provider.rate-limited"
            case .timeout: return "provider.timeout"
            case .cancelled: return "provider.cancelled"
            case .networkUnavailable: return "provider.network-unavailable"
            case .server: return "provider.server"
            case .incomplete: return "provider.incomplete"
            case .refused: return "provider.refused"
            case .malformedResponse: return "provider.malformed-response"
            case .oversizedResponse: return "provider.oversized-response"
            }
        }
        if let failure = error as? LocalWritingModelFailure {
            switch failure {
            case .invalidRequest: return "local.invalid-request"
            case .modelUnavailable: return "local.model-unavailable"
            case .cancelled: return "local.cancelled"
            case .generationFailed: return "local.generation-failed"
            case .malformedResponse: return "local.malformed-response"
            case .oversizedResponse: return "local.oversized-response"
            }
        }
        return "provider.unavailable"
    }

    private static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
