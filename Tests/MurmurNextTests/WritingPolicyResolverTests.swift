import Testing
@testable import MurmurNext

struct WritingPolicyResolverTests {
    private let mail = TargetApplicationDescriptor(
        processIdentifier: 42,
        bundleIdentifier: "com.apple.mail",
        localizedName: "Mail",
        writingContext: .email
    )

    @Test func deterministicRouteNeverRequestsGenerativeTransformation() {
        let policy = WritingPolicyResolver().resolve(
            settings: .default,
            target: mail,
            mode: .pushToTalk
        )

        #expect(policy.shouldTransform == false)
        #expect(policy.route == .deterministic)
        #expect(policy.allowedOutboundData.isEmpty)
        #expect(policy.fallback == .deterministicSource)
    }

    @Test func openAIEmailRequiresConsentAndUsesOnlyApprovedScope() {
        var denied = WritingSettings.default
        denied.route = .openAI
        let deniedPolicy = WritingPolicyResolver().resolve(
            settings: denied,
            target: mail,
            mode: .pushToTalk
        )
        #expect(deniedPolicy.shouldTransform == false)

        denied.remoteEmailTextAllowed = true
        let allowedPolicy = WritingPolicyResolver().resolve(
            settings: denied,
            target: mail,
            mode: .pushToTalk
        )

        #expect(allowedPolicy.shouldTransform)
        #expect(allowedPolicy.operation == .professionalEmail)
        #expect(allowedPolicy.route == .openAI)
        #expect(allowedPolicy.modelIdentifier == "gpt-5.6")
        #expect(allowedPolicy.instructionVersion == "professional-email-v1")
        #expect(allowedPolicy.allowedOutboundData == [
            .completedTranscript,
            .writingInstruction,
            .applicationCategory,
        ])
        #expect(allowedPolicy.allowedOutboundData.contains(.selectedText) == false)
    }

    @Test func localEmailNeedsNoRemoteTextConsent() {
        var settings = WritingSettings.default
        settings.route = .localMLX

        let policy = WritingPolicyResolver().resolve(
            settings: settings,
            target: mail,
            mode: .pushToTalk
        )

        #expect(policy.shouldTransform)
        #expect(policy.route == .localMLX)
        #expect(policy.modelIdentifier == WritingSettings.defaultLocalModelIdentifier)
        #expect(policy.allowedOutboundData.isEmpty)
    }

    @Test func perApplicationDisableWinsOverAutomaticEmailMode() {
        var settings = WritingSettings.default
        settings.route = .localMLX
        settings.disabledApplicationBundleIdentifiers = [mail.bundleIdentifier]

        let policy = WritingPolicyResolver().resolve(
            settings: settings,
            target: mail,
            mode: .pushToTalk
        )

        #expect(policy.shouldTransform == false)
        #expect(policy.disableReason == .applicationDisabled)
    }

    @Test func remoteCommandHasIndependentSelectedTextConsent() {
        var settings = WritingSettings.default
        settings.route = .openAI
        settings.remoteEmailTextAllowed = true

        let denied = WritingPolicyResolver().resolve(
            settings: settings,
            target: mail,
            mode: .command
        )
        #expect(denied.shouldTransform == false)
        #expect(denied.disableReason == .consentMissing)

        settings.remoteSelectedTextAllowed = true
        let allowed = WritingPolicyResolver().resolve(
            settings: settings,
            target: mail,
            mode: .command
        )
        #expect(allowed.shouldTransform)
        #expect(allowed.operation == .semanticCommand)
        #expect(allowed.allowedOutboundData == [
            .selectedText,
            .spokenInstruction,
            .writingInstruction,
            .applicationCategory,
        ])
        #expect(allowed.allowedOutboundData.contains(.completedTranscript) == false)
    }

    @Test func resolvedPolicyDoesNotChangeWhenSettingsChange() {
        var settings = WritingSettings.default
        settings.route = .openAI
        settings.remoteEmailTextAllowed = true
        let captured = WritingPolicyResolver().resolve(
            settings: settings,
            target: mail,
            mode: .pushToTalk
        )

        settings.route = .localMLX
        settings.openAIModelIdentifier = "changed-after-capture"

        #expect(captured.route == .openAI)
        #expect(captured.modelIdentifier == "gpt-5.6")
    }

    @Test func compatibleRouteCapturesOnlyAValidatedEndpoint() {
        var settings = WritingSettings.default
        settings.route = .openAICompatible
        settings.openAICompatibleModelIdentifier = "writer-model"
        settings.remoteEmailTextAllowed = true

        settings.openAICompatibleEndpoint = "http://writer.example.test/v1"
        let insecure = WritingPolicyResolver().resolve(
            settings: settings,
            target: mail,
            mode: .pushToTalk
        )
        #expect(insecure.shouldTransform == false)
        #expect(insecure.endpoint == nil)
        #expect(insecure.disableReason == .providerConfigurationMissing)

        settings.openAICompatibleEndpoint = "https://writer.example.test/v1/"
        let captured = WritingPolicyResolver().resolve(
            settings: settings,
            target: mail,
            mode: .pushToTalk
        )
        settings.openAICompatibleEndpoint = "https://changed.example.test/v1"

        #expect(captured.shouldTransform)
        #expect(captured.endpoint?.absoluteString == "https://writer.example.test/v1")
        #expect(captured.providerIdentifier == "openai-compatible")
        #expect(captured.modelIdentifier == "writer-model")
    }
}
