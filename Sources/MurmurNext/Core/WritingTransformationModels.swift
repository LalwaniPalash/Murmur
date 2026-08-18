import Foundation

enum WritingTransformationRoute: String, Codable, CaseIterable, Identifiable, Sendable {
    case deterministic
    case openAI
    case openAICompatible
    case localMLX

    var id: String { rawValue }

    var isRemote: Bool {
        self == .openAI || self == .openAICompatible
    }
}

enum LocalWritingModelSelectionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case preferred
    case fixed

    var id: String { rawValue }
}

struct WritingSettings: Codable, Equatable, Sendable {
    static let defaultOpenAIModelIdentifier = "gpt-5.6"
    static let defaultLocalModelIdentifier = "mlx-community/Qwen3-0.6B-4bit"

    var route: WritingTransformationRoute
    var emailModeEnabled: Bool
    var openAIModelIdentifier: String
    var openAICompatibleEndpoint: String?
    var openAICompatibleModelIdentifier: String
    var localModelIdentifier: String
    var localModelSelectionMode: LocalWritingModelSelectionMode
    var remoteEmailTextAllowed: Bool
    var remoteSelectedTextAllowed: Bool
    var browserDomainDetectionAllowed: Bool
    var disabledApplicationBundleIdentifiers: Set<String>

    static let `default` = WritingSettings(
        route: .deterministic,
        emailModeEnabled: true,
        openAIModelIdentifier: defaultOpenAIModelIdentifier,
        openAICompatibleEndpoint: nil,
        openAICompatibleModelIdentifier: "",
        localModelIdentifier: defaultLocalModelIdentifier,
        localModelSelectionMode: .automatic,
        remoteEmailTextAllowed: false,
        remoteSelectedTextAllowed: false,
        browserDomainDetectionAllowed: false,
        disabledApplicationBundleIdentifiers: []
    )

    init(
        route: WritingTransformationRoute,
        emailModeEnabled: Bool,
        openAIModelIdentifier: String,
        openAICompatibleEndpoint: String?,
        openAICompatibleModelIdentifier: String,
        localModelIdentifier: String,
        localModelSelectionMode: LocalWritingModelSelectionMode = .automatic,
        remoteEmailTextAllowed: Bool,
        remoteSelectedTextAllowed: Bool,
        browserDomainDetectionAllowed: Bool,
        disabledApplicationBundleIdentifiers: Set<String>
    ) {
        self.route = route
        self.emailModeEnabled = emailModeEnabled
        self.openAIModelIdentifier = openAIModelIdentifier
        self.openAICompatibleEndpoint = openAICompatibleEndpoint
        self.openAICompatibleModelIdentifier = openAICompatibleModelIdentifier
        self.localModelIdentifier = localModelIdentifier
        self.localModelSelectionMode = localModelSelectionMode
        self.remoteEmailTextAllowed = remoteEmailTextAllowed
        self.remoteSelectedTextAllowed = remoteSelectedTextAllowed
        self.browserDomainDetectionAllowed = browserDomainDetectionAllowed
        self.disabledApplicationBundleIdentifiers = disabledApplicationBundleIdentifiers
    }

    private enum CodingKeys: String, CodingKey {
        case route, emailModeEnabled, openAIModelIdentifier, openAICompatibleEndpoint
        case openAICompatibleModelIdentifier, localModelIdentifier, localModelSelectionMode
        case remoteEmailTextAllowed, remoteSelectedTextAllowed, browserDomainDetectionAllowed
        case disabledApplicationBundleIdentifiers
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        route = try values.decodeIfPresent(WritingTransformationRoute.self, forKey: .route) ?? .deterministic
        emailModeEnabled = try values.decodeIfPresent(Bool.self, forKey: .emailModeEnabled) ?? true
        openAIModelIdentifier = try values.decodeIfPresent(String.self, forKey: .openAIModelIdentifier) ?? Self.defaultOpenAIModelIdentifier
        openAICompatibleEndpoint = try values.decodeIfPresent(String.self, forKey: .openAICompatibleEndpoint)
        openAICompatibleModelIdentifier = try values.decodeIfPresent(String.self, forKey: .openAICompatibleModelIdentifier) ?? ""
        localModelIdentifier = try values.decodeIfPresent(String.self, forKey: .localModelIdentifier) ?? Self.defaultLocalModelIdentifier
        localModelSelectionMode = try values.decodeIfPresent(LocalWritingModelSelectionMode.self, forKey: .localModelSelectionMode) ?? .automatic
        remoteEmailTextAllowed = try values.decodeIfPresent(Bool.self, forKey: .remoteEmailTextAllowed) ?? false
        remoteSelectedTextAllowed = try values.decodeIfPresent(Bool.self, forKey: .remoteSelectedTextAllowed) ?? false
        browserDomainDetectionAllowed = try values.decodeIfPresent(Bool.self, forKey: .browserDomainDetectionAllowed) ?? false
        disabledApplicationBundleIdentifiers = try values.decodeIfPresent(Set<String>.self, forKey: .disabledApplicationBundleIdentifiers) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(route, forKey: .route)
        try values.encode(emailModeEnabled, forKey: .emailModeEnabled)
        try values.encode(openAIModelIdentifier, forKey: .openAIModelIdentifier)
        try values.encodeIfPresent(openAICompatibleEndpoint, forKey: .openAICompatibleEndpoint)
        try values.encode(openAICompatibleModelIdentifier, forKey: .openAICompatibleModelIdentifier)
        try values.encode(localModelIdentifier, forKey: .localModelIdentifier)
        try values.encode(localModelSelectionMode, forKey: .localModelSelectionMode)
        try values.encode(remoteEmailTextAllowed, forKey: .remoteEmailTextAllowed)
        try values.encode(remoteSelectedTextAllowed, forKey: .remoteSelectedTextAllowed)
        try values.encode(browserDomainDetectionAllowed, forKey: .browserDomainDetectionAllowed)
        try values.encode(disabledApplicationBundleIdentifiers, forKey: .disabledApplicationBundleIdentifiers)
    }
}

enum WritingTransformationOperation: String, Codable, Equatable, Sendable {
    case professionalEmail
    case semanticCommand
}

enum WritingOutboundDataCategory: String, Codable, Hashable, Sendable {
    case completedTranscript
    case selectedText
    case spokenInstruction
    case writingInstruction
    case applicationCategory
}

enum WritingTransformationFallback: String, Codable, Equatable, Sendable {
    case deterministicSource
}

enum WritingPolicyDisableReason: String, Codable, Equatable, Sendable {
    case deterministicRoute
    case unsupportedContext
    case emailModeDisabled
    case applicationDisabled
    case consentMissing
    case providerConfigurationMissing
}

struct CapturedWritingPolicy: Equatable, Sendable {
    let route: WritingTransformationRoute
    let operation: WritingTransformationOperation?
    let providerIdentifier: String?
    let modelIdentifier: String?
    let instructionVersion: String?
    let endpoint: URL?
    let allowedOutboundData: Set<WritingOutboundDataCategory>
    let timeoutSeconds: TimeInterval
    let fallback: WritingTransformationFallback
    let disableReason: WritingPolicyDisableReason?
    let localSelectionReason: String?
    let retryModelIdentifier: String?

    init(
        route: WritingTransformationRoute,
        operation: WritingTransformationOperation?,
        providerIdentifier: String?,
        modelIdentifier: String?,
        instructionVersion: String?,
        endpoint: URL? = nil,
        allowedOutboundData: Set<WritingOutboundDataCategory>,
        timeoutSeconds: TimeInterval,
        fallback: WritingTransformationFallback,
        disableReason: WritingPolicyDisableReason?,
        localSelectionReason: String? = nil,
        retryModelIdentifier: String? = nil
    ) {
        self.route = route
        self.operation = operation
        self.providerIdentifier = providerIdentifier
        self.modelIdentifier = modelIdentifier
        self.instructionVersion = instructionVersion
        self.endpoint = endpoint
        self.allowedOutboundData = allowedOutboundData
        self.timeoutSeconds = timeoutSeconds
        self.fallback = fallback
        self.disableReason = disableReason
        self.localSelectionReason = localSelectionReason
        self.retryModelIdentifier = retryModelIdentifier
    }

    var shouldTransform: Bool {
        route != .deterministic && operation != nil && disableReason == nil
    }
}

struct WritingTransformationRequest: Equatable, Sendable {
    let sourceText: String
    let spokenInstruction: String?
    let operation: WritingTransformationOperation
    let applicationCategory: String
    let policy: CapturedWritingPolicy
}

struct WritingTransformationUsage: Equatable, Sendable {
    let inputTokens: Int?
    let outputTokens: Int?
}

struct WritingTransformationResponse: Equatable, Sendable {
    let text: String
    let providerIdentifier: String
    let modelIdentifier: String
    let usage: WritingTransformationUsage?
}

enum TransformationProviderFailure: Error, Equatable, LocalizedError, Sendable {
    case invalidRequest
    case missingCredential
    case authentication
    case rateLimited
    case timeout
    case cancelled
    case networkUnavailable
    case server(Int)
    case incomplete
    case refused
    case malformedResponse
    case oversizedResponse

    var errorDescription: String? {
        switch self {
        case .invalidRequest: "The writing request was not safe to send."
        case .missingCredential: "Add a provider key before using cloud writing."
        case .authentication: "The provider rejected the configured key."
        case .rateLimited: "The provider is temporarily rate limited."
        case .timeout: "The writing provider took too long to respond."
        case .cancelled: "Writing was cancelled."
        case .networkUnavailable: "The writing provider is unavailable."
        case .server: "The writing provider returned a server error."
        case .incomplete: "The writing provider returned an incomplete result."
        case .refused: "The writing provider declined the request."
        case .malformedResponse: "The writing provider returned an invalid result."
        case .oversizedResponse: "The writing provider returned too much data."
        }
    }
}

protocol WritingTextTransformationEngine: Sendable {
    func transform(_ request: WritingTransformationRequest) async throws -> WritingTransformationResponse
}
