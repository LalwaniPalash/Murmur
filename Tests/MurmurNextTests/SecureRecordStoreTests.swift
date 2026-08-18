import CryptoKit
import Foundation
import Testing
@testable import MurmurNext

struct SecureRecordStoreTests {
    @Test func encryptedCodecRoundTripsAndRejectsTampering() throws {
        let key = SymmetricKey(data: Data(repeating: 0x2A, count: 32))
        let codec = EncryptedPayloadCodec(key: key)
        let original = SnippetItem(
            id: UUID(),
            trigger: "meeting link",
            expansion: "https://example.com/private",
            createdAt: Date(timeIntervalSince1970: 200)
        )

        let encrypted = try codec.encrypt(original)
        #expect(String(data: encrypted, encoding: .utf8) == nil)
        let decoded: SnippetItem = try codec.decrypt(encrypted)
        #expect(decoded == original)

        var tampered = encrypted
        tampered[tampered.index(before: tampered.endIndex)] ^= 0x01
        #expect(throws: (any Error).self) {
            let _: SnippetItem = try codec.decrypt(tampered)
        }
    }

    @Test func storesAndSearchesEncryptedRecordsUsingBlindTerms() async throws {
        let fixture = try StoreFixture()
        let store = try SecureRecordStore(url: fixture.databaseURL, key: fixture.key)
        let first = TranscriptRecord(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 300),
            sourceApplication: "Mail",
            sourceBundleIdentifier: "com.apple.mail",
            context: .email,
            mode: .pushToTalk,
            text: "Whisper the private launch notes.",
            duration: 4,
            wordsPerMinute: 75,
            insertionSucceeded: true
        )
        let second = TranscriptRecord(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 200),
            sourceApplication: "Messages",
            sourceBundleIdentifier: "com.apple.MobileSMS",
            context: .messaging,
            mode: .pushToTalk,
            text: "Dinner will be ready soon.",
            duration: 3,
            wordsPerMinute: 100,
            insertionSucceeded: true
        )

        try await store.save(first, collection: .history, searchableText: first.text)
        try await store.save(second, collection: .history, searchableText: second.text)

        let all: [TranscriptRecord] = try await store.fetch(collection: .history)
        let matches: [TranscriptRecord] = try await store.fetch(collection: .history, matching: "private whisper")
        #expect(all.map(\.id) == [first.id, second.id])
        #expect(matches.map(\.id) == [first.id])

        let rawDatabase = try Data(contentsOf: fixture.databaseURL)
        #expect(rawDatabase.range(of: Data("private launch notes".utf8)) == nil)
        #expect(rawDatabase.range(of: Data("https://example.com/private".utf8)) == nil)
    }

    @Test func replacesRecordsAtomicallyAndRemovesOldSearchTerms() async throws {
        let fixture = try StoreFixture()
        let store = try SecureRecordStore(url: fixture.databaseURL, key: fixture.key)
        var snippet = SnippetItem(
            id: UUID(),
            trigger: "old trigger",
            expansion: "Old expansion",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        try await store.save(snippet, collection: .snippets, searchableText: snippet.trigger)

        snippet.trigger = "new phrase"
        try await store.save(snippet, collection: .snippets, searchableText: snippet.trigger)

        let oldMatches: [SnippetItem] = try await store.fetch(collection: .snippets, matching: "old")
        let newMatches: [SnippetItem] = try await store.fetch(collection: .snippets, matching: "new")
        #expect(oldMatches.isEmpty)
        #expect(newMatches == [snippet])
    }

    @Test func deletionRemovesPayloadAndBlindIndex() async throws {
        let fixture = try StoreFixture()
        let store = try SecureRecordStore(url: fixture.databaseURL, key: fixture.key)
        let item = DictionaryItem(
            id: UUID(),
            spokenForm: "super base",
            writtenForm: "Supabase",
            context: .code,
            createdAt: Date()
        )
        try await store.save(item, collection: .dictionary, searchableText: "\(item.spokenForm) \(item.writtenForm)")
        try await store.delete(id: item.id, collection: .dictionary)

        let results: [DictionaryItem] = try await store.fetch(collection: .dictionary, matching: "Supabase")
        #expect(results.isEmpty)
    }

    @Test func backupRestoreAtomicallyReplacesAllUserCollections() async throws {
        let fixture = try StoreFixture()
        let store = try SecureRecordStore(url: fixture.databaseURL, key: fixture.key)
        let old = SnippetItem(id: UUID(), trigger: "old", expansion: "Old", createdAt: .now)
        try await store.save(old, collection: .snippets, searchableText: old.trigger)

        let restored = SnippetItem(id: UUID(), trigger: "restored", expansion: "Restored text", createdAt: .now)
        let note = ScratchpadNote(
            id: UUID(),
            title: "Recovered note",
            body: "Recovered body",
            isPinned: true,
            createdAt: .now,
            updatedAt: .now
        )
        let payload = MurmurBackupPayload(
            exportedAt: .now,
            history: [],
            dictionary: [],
            snippets: [restored],
            styles: [],
            notes: [note],
            settings: .default
        )

        try await store.restore(payload)

        let snippets: [SnippetItem] = try await store.fetch(collection: .snippets)
        let notes: [ScratchpadNote] = try await store.fetch(collection: .notes)
        let migratedSessions = try await store.fetchSourceSessions()
        let migratedResults = try await store.fetchResultVersions()
        #expect(snippets.map(\.id) == [restored.id])
        #expect(snippets.map(\.expansion) == [restored.expansion])
        #expect(notes.map(\.id) == [note.id])
        #expect(notes.map(\.body) == [note.body])
        #expect(snippets.contains(old) == false)
        #expect(migratedSessions.isEmpty)
        #expect(migratedResults.isEmpty)
    }

    @Test func appendsSessionAndFirstResultAtomicallyWithoutPlaintext() async throws {
        let fixture = try StoreFixture()
        let store = try SecureRecordStore(url: fixture.databaseURL, key: fixture.key)
        let session = Self.sourceSession()
        let result = Self.result(sessionID: session.id)

        try await store.append(session: session, firstResult: result)

        let sessions = try await store.fetchSourceSessions()
        let results = try await store.fetchResultVersions()
        let history = try await store.fetchVersionedHistory(matching: "private launch")
        let rawDatabase = try Data(contentsOf: fixture.databaseURL)
        #expect(sessions == [session])
        #expect(results == [result])
        #expect(history.map(\.text) == [result.finalTranscript])
        #expect(rawDatabase.range(of: Data(result.rawTranscript.utf8)) == nil)
        #expect(rawDatabase.range(of: Data(result.finalTranscript.utf8)) == nil)
    }

    @Test func appendOnlyRecordsRejectDuplicateIDs() async throws {
        let fixture = try StoreFixture()
        let store = try SecureRecordStore(url: fixture.databaseURL, key: fixture.key)
        let session = Self.sourceSession()
        let result = Self.result(sessionID: session.id)
        try await store.append(session: session, firstResult: result)

        await #expect(throws: SecureRecordStoreError.self) {
            try await store.append(session: session, firstResult: result)
        }

        #expect(try await store.fetchSourceSessions().count == 1)
        #expect(try await store.fetchResultVersions().count == 1)
    }

    @Test func validatesSessionAndParentBeforeAppendingResult() async throws {
        let fixture = try StoreFixture()
        let store = try SecureRecordStore(url: fixture.databaseURL, key: fixture.key)
        let firstSession = Self.sourceSession()
        let first = Self.result(sessionID: firstSession.id)
        try await store.append(session: firstSession, firstResult: first)

        let missingSessionResult = Self.result(sessionID: UUID())
        await #expect(throws: SecureRecordStoreError.self) {
            try await store.append(result: missingSessionResult)
        }

        let secondSession = Self.sourceSession()
        let second = Self.result(sessionID: secondSession.id)
        try await store.append(session: secondSession, firstResult: second)
        let crossSessionChild = Self.result(
            sessionID: secondSession.id,
            parentResultID: first.id
        )
        await #expect(throws: SecureRecordStoreError.self) {
            try await store.append(result: crossSessionChild)
        }
    }

    @Test func appendingChildPreservesParentAndProjectsNewestResult() async throws {
        let fixture = try StoreFixture()
        let store = try SecureRecordStore(url: fixture.databaseURL, key: fixture.key)
        let session = Self.sourceSession()
        let parent = Self.result(
            sessionID: session.id,
            createdAt: Date(timeIntervalSince1970: 110),
            finalTranscript: "Original final."
        )
        try await store.append(session: session, firstResult: parent)
        let child = Self.result(
            sessionID: session.id,
            parentResultID: parent.id,
            createdAt: Date(timeIntervalSince1970: 120),
            finalTranscript: "Improved final."
        )

        try await store.append(result: child)

        let results = try await store.fetchResultVersions()
        let history = try await store.fetchVersionedHistory()
        #expect(results.contains(parent))
        #expect(results.contains(child))
        #expect(history.map(\.text) == ["Improved final."])
    }

    @Test func migratesLegacyHistoryOnceWithoutDeletingRollbackRows() async throws {
        let fixture = try StoreFixture()
        let store = try SecureRecordStore(url: fixture.databaseURL, key: fixture.key)
        let legacy = TranscriptRecord(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 300),
            sourceApplication: "Messages",
            sourceBundleIdentifier: "com.apple.MobileSMS",
            context: .messaging,
            mode: .pushToTalk,
            text: "Legacy encrypted transcript.",
            duration: 3,
            wordsPerMinute: 60,
            insertionSucceeded: true
        )
        try await store.save(legacy, collection: .history, searchableText: legacy.text)
        #expect(try await store.schemaVersion() == 1)

        try await store.migrateHistoryToVersionedRecordsIfNeeded()
        try await store.migrateHistoryToVersionedRecordsIfNeeded()

        let sessions = try await store.fetchSourceSessions()
        let results = try await store.fetchResultVersions()
        let rollbackRows: [TranscriptRecord] = try await store.fetch(collection: .history)
        #expect(try await store.schemaVersion() == 2)
        #expect(sessions.map(\.id) == [legacy.id])
        #expect(results.map(\.id) == [legacy.id])
        #expect(results[0].rawTranscript == legacy.text)
        #expect(results[0].finalTranscript == legacy.text)
        #expect(results[0].providerIdentifier == SessionResultProvenance.legacyUnknown)
        #expect(rollbackRows == [legacy])
    }

    @Test func migrationConflictRollsBackEveryRecordAndSchemaVersion() async throws {
        let fixture = try StoreFixture()
        let store = try SecureRecordStore(url: fixture.databaseURL, key: fixture.key)
        let conflictingSession = Self.sourceSession()
        let conflictingResult = Self.result(sessionID: conflictingSession.id)
        try await store.append(session: conflictingSession, firstResult: conflictingResult)
        let legacy = TranscriptRecord(
            id: conflictingSession.id,
            createdAt: conflictingSession.startedAt,
            sourceApplication: "Mail",
            sourceBundleIdentifier: "com.apple.mail",
            context: .email,
            mode: .pushToTalk,
            text: "Conflicting legacy transcript.",
            duration: 4,
            wordsPerMinute: 45,
            insertionSucceeded: true
        )
        try await store.save(legacy, collection: .history, searchableText: legacy.text)

        await #expect(throws: SecureRecordStoreError.self) {
            try await store.migrateHistoryToVersionedRecordsIfNeeded()
        }

        #expect(try await store.schemaVersion() == 1)
        #expect(try await store.fetchSourceSessions() == [conflictingSession])
        #expect(try await store.fetchResultVersions() == [conflictingResult])
        let rollbackRows: [TranscriptRecord] = try await store.fetch(collection: .history)
        #expect(rollbackRows == [legacy])
    }

    @Test func restoreRejectsInvalidVersionGraphWithoutReplacingExistingRecords() async throws {
        let fixture = try StoreFixture()
        let store = try SecureRecordStore(url: fixture.databaseURL, key: fixture.key)
        let existing = SnippetItem(
            id: UUID(),
            trigger: "keep me",
            expansion: "Existing content",
            createdAt: Date(timeIntervalSince1970: 500)
        )
        try await store.save(existing, collection: .snippets, searchableText: existing.trigger)

        let orphanedSession = Self.sourceSession()
        let invalidBackup = MurmurBackupPayload(
            exportedAt: .now,
            history: [],
            dictionary: [],
            snippets: [],
            styles: [],
            notes: [],
            settings: .default,
            sourceSessions: [orphanedSession],
            resultVersions: []
        )

        await #expect(throws: SecureRecordStoreError.self) {
            try await store.restore(invalidBackup)
        }

        let snippets: [SnippetItem] = try await store.fetch(collection: .snippets)
        #expect(snippets == [existing])
        #expect(try await store.schemaVersion() == 1)
    }

    @Test func restorePreservesPreferredResultSelection() async throws {
        let fixture = try StoreFixture()
        let store = try SecureRecordStore(url: fixture.databaseURL, key: fixture.key)
        let session = Self.sourceSession()
        let first = Self.result(sessionID: session.id)
        let second = TranscriptResultVersion(
            id: UUID(),
            sessionID: session.id,
            parentResultID: first.id,
            createdAt: first.createdAt.addingTimeInterval(1),
            rawTranscript: "New raw text.",
            finalTranscript: "New final text.",
            providerIdentifier: "local-whisper",
            modelIdentifier: "medium.en",
            language: "en",
            totalProcessingDuration: 0.5,
            insertionSucceeded: false
        )
        let preferred = PreferredResultRecord(
            sessionID: session.id,
            resultID: first.id,
            updatedAt: .now
        )
        let payload = MurmurBackupPayload(
            exportedAt: .now,
            history: [],
            dictionary: [],
            snippets: [],
            styles: [],
            notes: [],
            settings: .default,
            sourceSessions: [session],
            resultVersions: [first, second],
            preferredResults: [preferred]
        )

        try await store.restore(payload)

        let restoredPreference = try #require(try await store.fetchPreferredResults().first)
        #expect(restoredPreference.sessionID == preferred.sessionID)
        #expect(restoredPreference.resultID == preferred.resultID)
        #expect(try await store.fetchVersionedHistory().first?.text == first.finalTranscript)
        #expect(Set(try await store.fetchResultVersions().map(\.id)) == Set([first.id, second.id]))
    }

    private static func sourceSession() -> SourceSessionRecord {
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

    private static func result(
        sessionID: UUID,
        parentResultID: UUID? = nil,
        createdAt: Date = Date(timeIntervalSince1970: 105),
        finalTranscript: String = "Private launch final text."
    ) -> TranscriptResultVersion {
        TranscriptResultVersion(
            id: UUID(),
            sessionID: sessionID,
            parentResultID: parentResultID,
            createdAt: createdAt,
            rawTranscript: "Private launch raw words.",
            finalTranscript: finalTranscript,
            providerIdentifier: "local-whisper",
            modelIdentifier: "small.en",
            language: "en",
            totalProcessingDuration: 0.3,
            insertionSucceeded: true
        )
    }
}

private struct StoreFixture {
    let directoryURL: URL
    let databaseURL: URL
    let key = SymmetricKey(data: Data(repeating: 0x3B, count: 32))

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmur-store-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        databaseURL = directoryURL.appendingPathComponent("store.sqlite")
    }
}
