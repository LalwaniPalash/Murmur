import CryptoKit
import Foundation
import Testing
@testable import MurmurNext

@Suite(.serialized)
struct RecoveryCoordinatorTests {
    @Test(arguments: [RecoveryPhase.capturing, .finalizing, .inserting])
    func interruptedAudioSessionOffersRetryRetainAndDelete(phase: RecoveryPhase) async throws {
        let fixture = try RecoveryFixture()
        let sessionID = UUID()
        let audio = fixture.audioRecord(id: sessionID, state: .sealed)
        try await fixture.store.saveRetainedAudio(audio)
        try await fixture.store.saveRecoveryJournal(fixture.journal(id: sessionID, phase: phase))

        let item = try #require(try await fixture.coordinator.reconcile().first)

        #expect(item.retainedAudio == audio)
        #expect(item.actions == [.retryTranscription, .retain, .delete])
    }

    @Test
    func interruptedInsertionWithFailedResultCanOnlyCopyOrDelete() async throws {
        let fixture = try RecoveryFixture()
        let session = fixture.session()
        let result = fixture.result(sessionID: session.id, insertionSucceeded: false)
        try await fixture.store.append(session: session, firstResult: result)
        try await fixture.store.saveRecoveryJournal(fixture.journal(id: session.id, phase: .inserting))

        let item = try #require(try await fixture.coordinator.reconcile().first)

        #expect(item.result == result)
        #expect(item.actions == [.copyText, .delete])
    }

    @Test
    func successfulPersistedInsertionClearsAStaleJournal() async throws {
        let fixture = try RecoveryFixture()
        let session = fixture.session()
        let result = fixture.result(sessionID: session.id, insertionSucceeded: true)
        try await fixture.store.append(session: session, firstResult: result)
        try await fixture.store.saveRecoveryJournal(fixture.journal(id: session.id, phase: .inserting))

        #expect(try await fixture.coordinator.reconcile().isEmpty)
        #expect(try await fixture.store.fetchRecoveryJournals().isEmpty)
    }

    @Test
    func audioMetadataSynthesizesRecoveryWhenCrashPrecedesJournalWrite() async throws {
        let fixture = try RecoveryFixture()
        let sessionID = UUID()
        try await fixture.store.saveRetainedAudio(fixture.audioRecord(id: sessionID, state: .capturing))

        let item = try #require(try await fixture.coordinator.reconcile().first)

        #expect(item.journal.phase == .capturing)
        #expect(item.journal.targetApplication == SessionResultProvenance.legacyUnknown)
        #expect(item.actions == [.retryTranscription, .retain, .delete])
    }

    @Test
    func cleanupJournalResumesIdempotently() async throws {
        let fixture = try RecoveryFixture()
        let session = fixture.session()
        let result = fixture.result(sessionID: session.id, insertionSucceeded: false)
        try await fixture.store.append(session: session, firstResult: result)
        try await fixture.store.saveRecoveryJournal(fixture.journal(id: session.id, phase: .cleaningUp))

        #expect(try await fixture.coordinator.reconcile().isEmpty)
        #expect(try await fixture.coordinator.reconcile().isEmpty)
        #expect(try await fixture.store.fetchRecoveryJournals().isEmpty)
        #expect(try await fixture.store.fetchSourceSessions().isEmpty)
        #expect(try await fixture.store.fetchResultVersions().isEmpty)
    }

    @Test
    func journalPayloadIsEncryptedAndContainsNoTranscript() async throws {
        let fixture = try RecoveryFixture()
        let journal = RecoveryJournalRecord(
            id: UUID(),
            updatedAt: .now,
            phase: .finalizing,
            targetApplication: "Private Canary Application",
            targetBundleIdentifier: "com.example.private-canary",
            retainedAudioAvailable: true,
            failureCode: "content-free-failure-code"
        )
        try await fixture.store.saveRecoveryJournal(journal)

        let database = try Data(contentsOf: fixture.databaseURL)
        #expect(database.range(of: Data("Private Canary Application".utf8)) == nil)
        #expect(database.range(of: Data("content-free-failure-code".utf8)) == nil)
    }
}

private struct RecoveryFixture {
    let directoryURL: URL
    let databaseURL: URL
    let store: SecureRecordStore
    let coordinator: RecoveryCoordinator

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmur-recovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        databaseURL = directoryURL.appendingPathComponent("store.sqlite")
        let key = SymmetricKey(data: Data(repeating: 0x73, count: 32))
        store = try SecureRecordStore(url: databaseURL, key: key)
        let retention = RetentionCoordinator(
            vault: EncryptedAudioVault(rootURL: directoryURL.appendingPathComponent("Audio"), masterKey: key),
            store: store
        )
        coordinator = RecoveryCoordinator(store: store, retention: retention)
    }

    func journal(id: UUID, phase: RecoveryPhase) -> RecoveryJournalRecord {
        RecoveryJournalRecord(
            id: id,
            updatedAt: Date(timeIntervalSince1970: 200),
            phase: phase,
            targetApplication: "Mail",
            targetBundleIdentifier: "com.apple.mail",
            retainedAudioAvailable: true
        )
    }

    func audioRecord(id: UUID, state: RetainedAudioState) -> RetainedAudioRecord {
        RetainedAudioRecord(
            id: id,
            createdAt: Date(timeIntervalSince1970: 100),
            expiresAt: nil,
            relativePath: state == .sealed
                ? "\(id.uuidString.lowercased()).mra"
                : "\(id.uuidString.lowercased()).mra.partial",
            wrappedKey: Data(repeating: 2, count: 60),
            sampleRate: 16_000,
            state: state
        )
    }

    func session() -> SourceSessionRecord {
        SourceSessionRecord(
            id: UUID(),
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 104),
            sourceApplication: "Mail",
            sourceBundleIdentifier: "com.apple.mail",
            context: .email,
            mode: .pushToTalk,
            recordingDuration: 4
        )
    }

    func result(sessionID: UUID, insertionSucceeded: Bool) -> TranscriptResultVersion {
        TranscriptResultVersion(
            id: UUID(),
            sessionID: sessionID,
            createdAt: Date(timeIntervalSince1970: 105),
            rawTranscript: "Raw recovered words.",
            finalTranscript: "Recovered words.",
            providerIdentifier: "local-whisper",
            modelIdentifier: "small.en",
            language: "en",
            totalProcessingDuration: 0.3,
            insertionSucceeded: insertionSucceeded
        )
    }
}
