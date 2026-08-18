import Foundation

enum SessionResultProvenance {
    static let legacyUnknown = "legacy-unknown"

    static func normalized(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? legacyUnknown : trimmed
    }
}

struct SourceSessionRecord: Identifiable, Codable, Equatable, Sendable {
    let schemaVersion: Int
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let sourceApplication: String
    let sourceBundleIdentifier: String?
    let context: WritingContext
    let mode: DictationMode
    let recordingDuration: TimeInterval

    init(
        schemaVersion: Int = 1,
        id: UUID,
        startedAt: Date,
        endedAt: Date,
        sourceApplication: String,
        sourceBundleIdentifier: String?,
        context: WritingContext,
        mode: DictationMode,
        recordingDuration: TimeInterval
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.sourceApplication = sourceApplication
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.context = context
        self.mode = mode
        self.recordingDuration = max(0, recordingDuration.isFinite ? recordingDuration : 0)
    }
}

enum TransformationProvenanceValidation: String, Codable, Equatable, Sendable {
    case accepted
    case rejected
    case providerFailed
}

struct WritingTransformationProvenance: Codable, Equatable, Sendable {
    let operation: WritingTransformationOperation
    let route: WritingTransformationRoute
    let providerIdentifier: String?
    let modelIdentifier: String?
    let instructionVersion: String?
    let sourceSHA256: String
    let sourceLength: Int
    let outputSHA256: String
    let outputLength: Int
    let duration: TimeInterval
    let validation: TransformationProvenanceValidation
    let failureCode: String?
    let selectionReason: String?
    let retryAttempted: Bool?
    let workerHealth: String?

    init(
        operation: WritingTransformationOperation,
        route: WritingTransformationRoute,
        providerIdentifier: String?,
        modelIdentifier: String?,
        instructionVersion: String?,
        sourceSHA256: String,
        sourceLength: Int,
        outputSHA256: String,
        outputLength: Int,
        duration: TimeInterval,
        validation: TransformationProvenanceValidation,
        failureCode: String?,
        selectionReason: String? = nil,
        retryAttempted: Bool? = nil,
        workerHealth: String? = nil
    ) {
        self.operation = operation
        self.route = route
        self.providerIdentifier = providerIdentifier
        self.modelIdentifier = modelIdentifier
        self.instructionVersion = instructionVersion
        self.sourceSHA256 = sourceSHA256
        self.sourceLength = sourceLength
        self.outputSHA256 = outputSHA256
        self.outputLength = outputLength
        self.duration = duration
        self.validation = validation
        self.failureCode = failureCode
        self.selectionReason = selectionReason
        self.retryAttempted = retryAttempted
        self.workerHealth = workerHealth
    }
}

struct TranscriptResultVersion: Identifiable, Codable, Equatable, Sendable {
    let schemaVersion: Int
    let id: UUID
    let sessionID: UUID
    let parentResultID: UUID?
    let createdAt: Date
    let rawTranscript: String
    let finalTranscript: String
    let providerIdentifier: String
    let modelIdentifier: String
    let language: String
    let totalProcessingDuration: TimeInterval
    let insertionSucceeded: Bool
    let writingTransformation: WritingTransformationProvenance?

    init(
        schemaVersion: Int = 2,
        id: UUID,
        sessionID: UUID,
        parentResultID: UUID? = nil,
        createdAt: Date,
        rawTranscript: String,
        finalTranscript: String,
        providerIdentifier: String,
        modelIdentifier: String,
        language: String,
        totalProcessingDuration: TimeInterval,
        insertionSucceeded: Bool,
        writingTransformation: WritingTransformationProvenance? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.sessionID = sessionID
        self.parentResultID = parentResultID
        self.createdAt = createdAt
        self.rawTranscript = rawTranscript
        self.finalTranscript = finalTranscript
        self.providerIdentifier = SessionResultProvenance.normalized(providerIdentifier)
        self.modelIdentifier = SessionResultProvenance.normalized(modelIdentifier)
        self.language = SessionResultProvenance.normalized(language)
        self.totalProcessingDuration = max(
            0,
            totalProcessingDuration.isFinite ? totalProcessingDuration : 0
        )
        self.insertionSucceeded = insertionSucceeded
        self.writingTransformation = writingTransformation
    }
}

enum SessionResultProjectionError: Error, Equatable, Sendable {
    case missingResult(UUID)
}

enum SessionResultGraphValidationError: Error, Equatable, Sendable {
    case duplicateSession(UUID)
    case duplicateResult(UUID)
    case missingResult(UUID)
    case missingSession(UUID)
    case invalidParent(UUID)
    case parentCycle(UUID)
}

enum SessionResultGraphValidator {
    static func validate(
        sessions: [SourceSessionRecord],
        results: [TranscriptResultVersion]
    ) throws {
        let sessionsByID = Dictionary(grouping: sessions, by: \.id)
        if let duplicate = sessionsByID.first(where: { $0.value.count != 1 })?.key {
            throw SessionResultGraphValidationError.duplicateSession(duplicate)
        }

        let resultsByID = Dictionary(grouping: results, by: \.id)
        if let duplicate = resultsByID.first(where: { $0.value.count != 1 })?.key {
            throw SessionResultGraphValidationError.duplicateResult(duplicate)
        }
        let uniqueResults = resultsByID.mapValues { $0[0] }
        let sessionsWithResults = Set(results.map(\.sessionID))

        for session in sessions where sessionsWithResults.contains(session.id) == false {
            throw SessionResultGraphValidationError.missingResult(session.id)
        }
        for result in results {
            guard sessionsByID[result.sessionID] != nil else {
                throw SessionResultGraphValidationError.missingSession(result.sessionID)
            }
            if let parentID = result.parentResultID {
                guard let parent = uniqueResults[parentID],
                      parent.sessionID == result.sessionID,
                      parent.id != result.id
                else { throw SessionResultGraphValidationError.invalidParent(result.id) }
            }
        }

        var resolved: Set<UUID> = []
        for result in results where resolved.contains(result.id) == false {
            var path: [UUID] = []
            var pathIDs: Set<UUID> = []
            var currentID: UUID? = result.id
            while let id = currentID, resolved.contains(id) == false {
                guard pathIDs.insert(id).inserted else {
                    throw SessionResultGraphValidationError.parentCycle(result.id)
                }
                path.append(id)
                currentID = uniqueResults[id]?.parentResultID
            }
            resolved.formUnion(path)
        }
    }
}

enum SessionResultProjection {
    static func preferredResult(
        for sessionID: UUID,
        results: [TranscriptResultVersion]
    ) throws -> TranscriptResultVersion {
        guard let preferred = results
            .filter({ $0.sessionID == sessionID })
            .max(by: { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            })
        else { throw SessionResultProjectionError.missingResult(sessionID) }
        return preferred
    }

    static func history(
        session: SourceSessionRecord,
        results: [TranscriptResultVersion],
        preferredResultID: UUID? = nil
    ) throws -> TranscriptRecord {
        let sessionResults = results.filter { $0.sessionID == session.id }
        let result: TranscriptResultVersion
        if let preferredResultID,
           let preferred = sessionResults.first(where: { $0.id == preferredResultID }) {
            result = preferred
        } else {
            result = try preferredResult(for: session.id, results: sessionResults)
        }
        let wordCount = result.finalTranscript.split(whereSeparator: \.isWhitespace).count
        let wordsPerMinute = session.recordingDuration > 0
            ? Double(wordCount) / (session.recordingDuration / 60)
            : 0
        return TranscriptRecord(
            id: session.id,
            createdAt: session.startedAt,
            sourceApplication: session.sourceApplication,
            sourceBundleIdentifier: session.sourceBundleIdentifier,
            context: session.context,
            mode: session.mode,
            text: result.finalTranscript,
            duration: session.recordingDuration,
            wordsPerMinute: wordsPerMinute,
            insertionSucceeded: result.insertionSucceeded
        )
    }
}

struct LegacySessionResultConversion: Equatable, Sendable {
    let session: SourceSessionRecord
    let result: TranscriptResultVersion
}

enum LegacySessionResultConverter {
    static func convert(_ legacy: TranscriptRecord) -> LegacySessionResultConversion {
        let endedAt = legacy.createdAt.addingTimeInterval(max(0, legacy.duration))
        return LegacySessionResultConversion(
            session: SourceSessionRecord(
                id: legacy.id,
                startedAt: legacy.createdAt,
                endedAt: endedAt,
                sourceApplication: legacy.sourceApplication,
                sourceBundleIdentifier: legacy.sourceBundleIdentifier,
                context: legacy.context,
                mode: legacy.mode,
                recordingDuration: legacy.duration
            ),
            result: TranscriptResultVersion(
                id: legacy.id,
                sessionID: legacy.id,
                createdAt: endedAt,
                rawTranscript: legacy.text,
                finalTranscript: legacy.text,
                providerIdentifier: SessionResultProvenance.legacyUnknown,
                modelIdentifier: SessionResultProvenance.legacyUnknown,
                language: SessionResultProvenance.legacyUnknown,
                totalProcessingDuration: 0,
                insertionSucceeded: legacy.insertionSucceeded
            )
        )
    }
}
