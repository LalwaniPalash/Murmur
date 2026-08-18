import Foundation

public enum QualityJSON {
    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public enum QualityGateCheckStatus: String, Codable, Equatable, Sendable {
    case passed
    case failed
    case notRun
}

public struct QualityGateCheck: Codable, Equatable, Sendable {
    public let id: String
    public let status: QualityGateCheckStatus
    public let summary: String

    public init(id: String, status: QualityGateCheckStatus, summary: String) {
        self.id = id
        self.status = status
        self.summary = summary
    }
}

public enum QualityGateOverallStatus: String, Codable, Equatable, Sendable {
    case passed
    case failed
    case incomplete
}

public struct QualityGateReport: Codable, Equatable, Sendable {
    public let format: String
    public let version: Int
    public let generatedAt: Date
    public let baselineCommit: String?
    public let checks: [QualityGateCheck]
    public let overallStatus: QualityGateOverallStatus

    public init(
        generatedAt: Date,
        baselineCommit: String?,
        checks: [QualityGateCheck],
        format: String = "murmur-quality-gate",
        version: Int = 1
    ) {
        self.format = format
        self.version = version
        self.generatedAt = generatedAt
        self.baselineCommit = baselineCommit
        self.checks = checks
        if checks.contains(where: { $0.status == .failed }) {
            overallStatus = .failed
        } else if checks.isEmpty || checks.contains(where: { $0.status == .notRun }) {
            overallStatus = .incomplete
        } else {
            overallStatus = .passed
        }
    }
}
