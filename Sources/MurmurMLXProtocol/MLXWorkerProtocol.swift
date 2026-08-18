import Foundation

public enum MLXWorkerProtocolLimits {
    public static let version = 2
    public static let maximumRequestBytes = 196_608
    public static let maximumResponseBytes = 393_216
    public static let maximumSourceBytes = 65_536
    public static let maximumInstructionBytes = 4_096
    public static let maximumProtectedTerms = 256
    public static let maximumProtectedTermBytes = 512
    public static let maximumOutputTokens = 2_048
}

public struct MLXWorkerRequest: Codable, Equatable, Sendable {
    public let version: Int
    public let requestID: UUID
    public let modelIdentifier: String
    public let modelDirectoryPath: String
    public let operation: String
    public let sourceText: String
    public let spokenInstruction: String?
    public let protectedTerms: [String]
    public let outputTokenLimit: Int

    public init(
        version: Int = MLXWorkerProtocolLimits.version,
        requestID: UUID = UUID(),
        modelIdentifier: String,
        modelDirectoryPath: String,
        operation: String,
        sourceText: String,
        spokenInstruction: String?,
        protectedTerms: [String],
        outputTokenLimit: Int
    ) {
        self.version = version
        self.requestID = requestID
        self.modelIdentifier = modelIdentifier
        self.modelDirectoryPath = modelDirectoryPath
        self.operation = operation
        self.sourceText = sourceText
        self.spokenInstruction = spokenInstruction
        self.protectedTerms = protectedTerms
        self.outputTokenLimit = outputTokenLimit
    }

    public func validate() throws {
        guard version == MLXWorkerProtocolLimits.version,
              (1...128).contains(modelIdentifier.utf8.count),
              modelDirectoryPath.utf8.count <= 4_096,
              modelDirectoryPath.hasPrefix("/"),
              operation == "professional-email" || operation == "semantic-command",
              sourceText.isEmpty == false,
              sourceText.utf8.count <= MLXWorkerProtocolLimits.maximumSourceBytes,
              (spokenInstruction?.utf8.count ?? 0) <= MLXWorkerProtocolLimits.maximumInstructionBytes,
              protectedTerms.count <= MLXWorkerProtocolLimits.maximumProtectedTerms,
              protectedTerms.allSatisfy({ $0.utf8.count <= MLXWorkerProtocolLimits.maximumProtectedTermBytes }),
              (1...MLXWorkerProtocolLimits.maximumOutputTokens).contains(outputTokenLimit)
        else { throw MLXWorkerProtocolError.invalidRequest }
    }
}

public struct MLXWorkerResponse: Codable, Equatable, Sendable {
    public let version: Int
    public let requestID: UUID
    public let status: String
    public let outputText: String?
    public let modelIdentifier: String?
    public let elapsedMilliseconds: Int?
    public let failureCode: String?

    public init(
        version: Int = MLXWorkerProtocolLimits.version,
        requestID: UUID,
        status: String,
        outputText: String? = nil,
        modelIdentifier: String? = nil,
        elapsedMilliseconds: Int? = nil,
        failureCode: String? = nil
    ) {
        self.version = version
        self.requestID = requestID
        self.status = status
        self.outputText = outputText
        self.modelIdentifier = modelIdentifier
        self.elapsedMilliseconds = elapsedMilliseconds
        self.failureCode = failureCode
    }
}

public enum MLXWorkerProtocolError: Error, Equatable, Sendable {
    case invalidRequest
    case oversizedPayload
    case invalidResponse
}

public enum MLXWorkerCodec {
    public static func encode(_ request: MLXWorkerRequest) throws -> Data {
        try request.validate()
        let data = try JSONEncoder().encode(request)
        guard data.count <= MLXWorkerProtocolLimits.maximumRequestBytes else {
            throw MLXWorkerProtocolError.oversizedPayload
        }
        return data
    }

    public static func decodeRequest(_ data: Data) throws -> MLXWorkerRequest {
        guard data.count <= MLXWorkerProtocolLimits.maximumRequestBytes else {
            throw MLXWorkerProtocolError.oversizedPayload
        }
        let request = try JSONDecoder().decode(MLXWorkerRequest.self, from: data)
        try request.validate()
        return request
    }

    public static func decodeResponse(_ data: Data, requestID: UUID) throws -> MLXWorkerResponse {
        guard data.count <= MLXWorkerProtocolLimits.maximumResponseBytes else {
            throw MLXWorkerProtocolError.oversizedPayload
        }
        let response = try JSONDecoder().decode(MLXWorkerResponse.self, from: data)
        guard response.version == MLXWorkerProtocolLimits.version,
              response.requestID == requestID,
              ["ok", "failed"].contains(response.status),
              response.status == "ok" ? response.outputText?.isEmpty == false : response.failureCode?.isEmpty == false
        else { throw MLXWorkerProtocolError.invalidResponse }
        return response
    }
}
