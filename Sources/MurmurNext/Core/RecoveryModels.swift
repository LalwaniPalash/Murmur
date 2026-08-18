import Foundation

enum RetainedAudioState: String, Codable, Equatable, Sendable {
    case capturing
    case sealed
}

struct RetainedAudioRecord: Identifiable, Codable, Equatable, Sendable {
    let schemaVersion: Int
    let id: UUID
    let createdAt: Date
    let expiresAt: Date?
    let relativePath: String
    let wrappedKey: Data
    let sampleRate: Int
    let sampleCount: Int
    let chunkCount: Int
    let byteCount: Int
    let state: RetainedAudioState

    init(
        schemaVersion: Int = 1,
        id: UUID,
        createdAt: Date,
        expiresAt: Date?,
        relativePath: String,
        wrappedKey: Data,
        sampleRate: Int,
        sampleCount: Int = 0,
        chunkCount: Int = 0,
        byteCount: Int = 0,
        state: RetainedAudioState = .capturing
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.relativePath = relativePath
        self.wrappedKey = wrappedKey
        self.sampleRate = sampleRate
        self.sampleCount = sampleCount
        self.chunkCount = chunkCount
        self.byteCount = byteCount
        self.state = state
    }
}

enum RecoveryPhase: String, Codable, Equatable, Sendable {
    case capturing
    case finalizing
    case inserting
    case cleaningUp
}

struct RecoveryJournalRecord: Identifiable, Codable, Equatable, Sendable {
    let schemaVersion: Int
    let id: UUID
    let updatedAt: Date
    let phase: RecoveryPhase
    let targetApplication: String
    let targetBundleIdentifier: String?
    let retainedAudioAvailable: Bool
    let resultID: UUID?
    let failureCode: String?

    init(
        schemaVersion: Int = 1,
        id: UUID,
        updatedAt: Date,
        phase: RecoveryPhase,
        targetApplication: String,
        targetBundleIdentifier: String?,
        retainedAudioAvailable: Bool,
        resultID: UUID? = nil,
        failureCode: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.updatedAt = updatedAt
        self.phase = phase
        self.targetApplication = targetApplication
        self.targetBundleIdentifier = targetBundleIdentifier
        self.retainedAudioAvailable = retainedAudioAvailable
        self.resultID = resultID
        self.failureCode = failureCode
    }
}

enum RecoveryAction: String, Codable, Equatable, CaseIterable, Sendable {
    case retryTranscription
    case retain
    case copyText
    case delete
}

struct RecoveryItem: Identifiable, Equatable, Sendable {
    var id: UUID { journal.id }
    let journal: RecoveryJournalRecord
    let retainedAudio: RetainedAudioRecord?
    let result: TranscriptResultVersion?
    let actions: [RecoveryAction]
}
