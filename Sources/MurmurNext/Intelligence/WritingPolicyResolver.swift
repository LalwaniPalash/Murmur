import Foundation

struct WritingPolicyResolver: Sendable {
    func resolve(
        settings: WritingSettings,
        target: TargetApplicationDescriptor,
        mode: DictationMode,
        installedLocalWritingModelIdentifiers: Set<String>? = nil
    ) -> CapturedWritingPolicy {
        let operation: WritingTransformationOperation?
        if mode == .command {
            operation = .semanticCommand
        } else if target.writingContext == .email {
            operation = .professionalEmail
        } else {
            operation = nil
        }

        let routeDetails = routeDetails(
            settings,
            operation: operation,
            installedIdentifiers: installedLocalWritingModelIdentifiers
        )
        let disableReason = disableReason(
            settings: settings,
            target: target,
            operation: operation,
            endpoint: routeDetails.endpoint,
            model: routeDetails.model
        )

        return CapturedWritingPolicy(
            route: settings.route,
            operation: operation,
            providerIdentifier: routeDetails.provider,
            modelIdentifier: routeDetails.model,
            instructionVersion: operation.map(instructionVersion),
            endpoint: routeDetails.endpoint,
            allowedOutboundData: disableReason == nil
                ? outboundData(for: operation, route: settings.route)
                : [],
            timeoutSeconds: settings.route.isRemote ? 8 : 15,
            fallback: .deterministicSource,
            disableReason: disableReason,
            localSelectionReason: routeDetails.selectionReason,
            retryModelIdentifier: routeDetails.retryModel
        )
    }

    private func disableReason(
        settings: WritingSettings,
        target: TargetApplicationDescriptor,
        operation: WritingTransformationOperation?,
        endpoint: URL?,
        model: String?
    ) -> WritingPolicyDisableReason? {
        guard settings.route != .deterministic else { return .deterministicRoute }
        guard let operation else { return .unsupportedContext }
        guard model != nil else { return .providerConfigurationMissing }
        if settings.route == .openAICompatible, endpoint == nil {
            return .providerConfigurationMissing
        }

        if settings.disabledApplicationBundleIdentifiers.contains(where: {
            $0.caseInsensitiveCompare(target.bundleIdentifier) == .orderedSame
        }) {
            return .applicationDisabled
        }

        switch operation {
        case .professionalEmail:
            guard settings.emailModeEnabled else { return .emailModeDisabled }
            if settings.route.isRemote && settings.remoteEmailTextAllowed == false {
                return .consentMissing
            }
        case .semanticCommand:
            if settings.route.isRemote && settings.remoteSelectedTextAllowed == false {
                return .consentMissing
            }
        }
        return nil
    }

    private func routeDetails(
        _ settings: WritingSettings,
        operation: WritingTransformationOperation?,
        installedIdentifiers: Set<String>?
    ) -> (provider: String?, model: String?, endpoint: URL?, selectionReason: String?, retryModel: String?) {
        switch settings.route {
        case .deterministic:
            return (nil, nil, nil, nil, nil)
        case .openAI:
            return ("openai", normalized(settings.openAIModelIdentifier), nil, nil, nil)
        case .openAICompatible:
            return (
                "openai-compatible",
                normalized(settings.openAICompatibleModelIdentifier),
                settings.openAICompatibleEndpoint.flatMap { try? TransformationEndpointPolicy.validate($0) },
                nil,
                nil
            )
        case .localMLX:
            if let operation, let installedIdentifiers {
                let selected = LocalWritingModelSelector().select(
                    mode: settings.localModelSelectionMode,
                    preferredIdentifier: settings.localModelIdentifier,
                    operation: operation,
                    installedIdentifiers: installedIdentifiers
                )
                return ("local-mlx", selected?.identifier, nil, selected?.reason, selected?.retryIdentifier)
            }
            return ("local-mlx", normalized(settings.localModelIdentifier), nil, nil, nil)
        }
    }

    private func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func instructionVersion(_ operation: WritingTransformationOperation) -> String {
        switch operation {
        case .professionalEmail: "professional-email-v1"
        case .semanticCommand: "semantic-command-v1"
        }
    }

    private func outboundData(
        for operation: WritingTransformationOperation?,
        route: WritingTransformationRoute
    ) -> Set<WritingOutboundDataCategory> {
        guard route.isRemote, let operation else { return [] }
        switch operation {
        case .professionalEmail:
            return Set([
                WritingOutboundDataCategory.completedTranscript,
                .writingInstruction,
                .applicationCategory,
            ])
        case .semanticCommand:
            return Set([
                WritingOutboundDataCategory.selectedText,
                .spokenInstruction,
                .writingInstruction,
                .applicationCategory,
            ])
        }
    }
}
