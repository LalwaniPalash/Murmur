import Foundation
import MurmurQualityCore

struct PreferredResultRecord: Identifiable, Codable, Equatable, Sendable {
    var id: UUID { sessionID }
    let schemaVersion: Int
    let sessionID: UUID
    let resultID: UUID
    let updatedAt: Date

    init(
        schemaVersion: Int = 1,
        sessionID: UUID,
        resultID: UUID,
        updatedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.sessionID = sessionID
        self.resultID = resultID
        self.updatedAt = updatedAt
    }
}

enum ResultVersionComparisonError: Error, Equatable, LocalizedError {
    case differentSessions

    var errorDescription: String? {
        "Only results from the same recording can be compared."
    }
}

struct ResultVersionComparison: Equatable, Sendable {
    let baseline: TranscriptResultVersion
    let candidate: TranscriptResultVersion
    let alignment: TranscriptAlignmentResult
}

enum ResultVersionComparisonService {
    static func compare(
        baseline: TranscriptResultVersion,
        candidate: TranscriptResultVersion
    ) throws -> ResultVersionComparison {
        guard baseline.sessionID == candidate.sessionID else {
            throw ResultVersionComparisonError.differentSessions
        }
        return ResultVersionComparison(
            baseline: baseline,
            candidate: candidate,
            alignment: TranscriptAligner.align(
                expected: baseline.finalTranscript,
                actual: candidate.finalTranscript
            )
        )
    }
}
