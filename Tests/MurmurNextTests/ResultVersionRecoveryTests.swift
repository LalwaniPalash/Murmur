import CryptoKit
import Foundation
import MurmurQualityCore
import Testing
@testable import MurmurNext

@Suite(.serialized)
struct ResultVersionRecoveryTests {
    @Test
    func retranscriptionAppendsChildAndSelectsItWithoutMutatingParent() async throws {
        let fixture = try ResultRecoveryFixture()
        let session = fixture.session()
        let parent = fixture.result(sessionID: session.id, text: "Original words.")
        try await fixture.store.append(session: session, firstResult: parent)
        try await fixture.retain(sessionID: session.id)
        let retained = try #require(try await fixture.store.fetchRetainedAudio().first)
        #expect(retained.relativePath == "\(session.id.uuidString.lowercased()).mra")
        #expect(try await fixture.retention.samples(sessionID: session.id).samples.isEmpty == false)
        let engine = TestTranscriptionEngine(text: "Um improved words.")
        let service = RetainedAudioRetranscriptionService(
            retention: fixture.retention,
            store: fixture.store,
            engine: engine
        )

        let child = try await service.retranscribe(
            sessionID: session.id,
            parentResultID: parent.id,
            model: try fixture.model(identifier: "medium.en"),
            settings: .default,
            dictionary: [],
            snippets: []
        )

        let results = try await fixture.store.fetchResultVersions()
        #expect(results.contains { $0.id == parent.id && $0.finalTranscript == parent.finalTranscript })
        #expect(results.contains { $0.id == child.id && $0.finalTranscript == child.finalTranscript })
        #expect(child.parentResultID == parent.id)
        #expect(child.rawTranscript == "Um improved words.")
        #expect(child.finalTranscript == "Improved words.")
        #expect(child.modelIdentifier == "medium.en")
        #expect(try await fixture.store.fetchPreferredResults().first?.resultID == child.id)
        #expect(try await fixture.store.fetchVersionedHistory().first?.text == "Improved words.")
    }

    @Test
    func selectingOlderPreferredResultPreservesNewerVersions() async throws {
        let fixture = try ResultRecoveryFixture()
        let session = fixture.session()
        let first = fixture.result(sessionID: session.id, text: "First version.")
        try await fixture.store.append(session: session, firstResult: first)
        let second = fixture.result(
            sessionID: session.id,
            parentID: first.id,
            text: "Second version."
        )
        try await fixture.store.append(result: second)

        try await fixture.store.savePreferredResult(PreferredResultRecord(
            sessionID: session.id,
            resultID: first.id,
            updatedAt: .now
        ))

        #expect(try await fixture.store.fetchVersionedHistory().first?.text == "First version.")
        #expect(Set(try await fixture.store.fetchResultVersions().map(\.id)) == Set([first.id, second.id]))
    }

    @Test
    func comparisonReportsInsertionsDeletionsAndSubstitutionsDeterministically() throws {
        let sessionID = UUID()
        let baseline = ResultRecoveryFixture.makeResult(
            sessionID: sessionID,
            text: "alpha beta gamma"
        )
        let candidate = ResultRecoveryFixture.makeResult(
            sessionID: sessionID,
            text: "alpha bright gamma"
        )

        let first = try ResultVersionComparisonService.compare(
            baseline: baseline,
            candidate: candidate
        )
        let second = try ResultVersionComparisonService.compare(
            baseline: baseline,
            candidate: candidate
        )

        #expect(first == second)
        #expect(first.alignment.operations.contains { $0.kind == .substitution })
        #expect(first.alignment.wordErrorRate > 0)

        let insertion = try ResultVersionComparisonService.compare(
            baseline: ResultRecoveryFixture.makeResult(sessionID: sessionID, text: "alpha beta"),
            candidate: ResultRecoveryFixture.makeResult(sessionID: sessionID, text: "alpha extra beta")
        )
        let deletion = try ResultVersionComparisonService.compare(
            baseline: ResultRecoveryFixture.makeResult(sessionID: sessionID, text: "alpha remove beta"),
            candidate: ResultRecoveryFixture.makeResult(sessionID: sessionID, text: "alpha beta")
        )
        #expect(insertion.alignment.operations.contains { $0.kind == .insertion })
        #expect(deletion.alignment.operations.contains { $0.kind == .deletion })
    }

    @Test
    func runtimeThatRequiresPlaintextFileIsRejectedBeforeAudioDecryption() async throws {
        let fixture = try ResultRecoveryFixture()
        let service = RetainedAudioRetranscriptionService(
            retention: fixture.retention,
            store: fixture.store,
            engine: PlaintextOnlyEngine()
        )

        await #expect(throws: RetainedRetranscriptionError.self) {
            _ = try await service.retranscribe(
                sessionID: UUID(),
                parentResultID: UUID(),
                model: try fixture.model(identifier: "test"),
                settings: .default,
                dictionary: [],
                snippets: []
            )
        }
    }

    @Test
    func interruptedCaptureCanBeRecoveredWithoutAnExistingSessionAndNeverInserts() async throws {
        let fixture = try ResultRecoveryFixture()
        let sessionID = UUID()
        try await fixture.retain(sessionID: sessionID)
        let retained = try #require(try await fixture.store.fetchRetainedAudio().first)
        let journal = RecoveryJournalRecord(
            id: sessionID,
            updatedAt: Date(timeIntervalSince1970: 105),
            phase: .finalizing,
            targetApplication: "Mail",
            targetBundleIdentifier: "com.apple.mail",
            retainedAudioAvailable: true,
            failureCode: "interrupted"
        )
        let service = RetainedAudioRetranscriptionService(
            retention: fixture.retention,
            store: fixture.store,
            engine: TestTranscriptionEngine(text: "Recovered whole recording.")
        )

        let result = try await service.recover(
            item: RecoveryItem(
                journal: journal,
                retainedAudio: retained,
                result: nil,
                actions: [.retryTranscription, .retain, .delete]
            ),
            model: try fixture.model(identifier: "small.en"),
            settings: .default,
            dictionary: [],
            snippets: []
        )

        #expect(result.sessionID == sessionID)
        #expect(result.finalTranscript == "Recovered whole recording.")
        #expect(result.insertionSucceeded == false)
        #expect(try await fixture.store.fetchSourceSessions().first?.sourceApplication == "Mail")
        #expect(try await fixture.store.fetchVersionedHistory().first?.text == result.finalTranscript)
    }
}

private actor PlaintextOnlyEngine: LocalTranscriptionEngine {
    nonisolated let supportsPersistentFileFreeTranscription = false
    func warmup(model: LocalWhisperModel) {}
    func transcribe(_ request: LocalTranscriptionRequest) throws -> LocalTranscriptionResult {
        throw LocalTranscriptionError.runtimeUnavailable
    }
    func cancel() {}
}

private struct ResultRecoveryFixture {
    let directoryURL: URL
    let store: SecureRecordStore
    let retention: RetentionCoordinator

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmur-result-recovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let audioURL = directoryURL.appendingPathComponent("Audio", isDirectory: true)
        try FileManager.default.createDirectory(at: audioURL, withIntermediateDirectories: true)
        let key = SymmetricKey(data: Data(repeating: 0x95, count: 32))
        store = try SecureRecordStore(url: directoryURL.appendingPathComponent("store.sqlite"), key: key)
        retention = RetentionCoordinator(
            vault: EncryptedAudioVault(rootURL: audioURL, masterKey: key),
            store: store
        )
    }

    func retain(sessionID: UUID) async throws {
        _ = try await retention.begin(
            sessionID: sessionID,
            policy: .sevenDays,
            sampleRate: 16_000,
            createdAt: .now
        )
        try await retention.append([0.1, -0.2, 0.3], sessionID: sessionID)
        _ = try await retention.finalize(sessionID: sessionID)
    }

    func model(identifier: String) throws -> LocalWhisperModel {
        let url = directoryURL.appendingPathComponent("\(identifier).bin")
        try Data([1]).write(to: url, options: .atomic)
        return LocalWhisperModel(identifier: identifier, fileURL: url, byteCount: 1, sha256: "test")
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

    func result(
        sessionID: UUID,
        parentID: UUID? = nil,
        text: String
    ) -> TranscriptResultVersion {
        Self.makeResult(sessionID: sessionID, parentID: parentID, text: text)
    }

    static func makeResult(
        sessionID: UUID,
        parentID: UUID? = nil,
        text: String
    ) -> TranscriptResultVersion {
        TranscriptResultVersion(
            id: UUID(),
            sessionID: sessionID,
            parentResultID: parentID,
            createdAt: Date(),
            rawTranscript: text,
            finalTranscript: text,
            providerIdentifier: "local-whisper",
            modelIdentifier: "small.en",
            language: "en",
            totalProcessingDuration: 0.2,
            insertionSucceeded: true
        )
    }
}
