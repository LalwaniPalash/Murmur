import Foundation

actor RecoveryCoordinator {
    private let store: SecureRecordStore
    private let retention: RetentionCoordinator

    init(store: SecureRecordStore, retention: RetentionCoordinator) {
        self.store = store
        self.retention = retention
    }

    func record(_ journal: RecoveryJournalRecord) async throws {
        try await store.saveRecoveryJournal(journal)
    }

    func clear(sessionID: UUID) async throws {
        try await store.deleteRecoveryJournal(id: sessionID)
    }

    func deleteRecovery(sessionID: UUID) async throws {
        let cleaning = RecoveryJournalRecord(
            id: sessionID,
            updatedAt: Date(),
            phase: .cleaningUp,
            targetApplication: SessionResultProvenance.legacyUnknown,
            targetBundleIdentifier: nil,
            retainedAudioAvailable: true
        )
        try await store.saveRecoveryJournal(cleaning)
        try await retention.deleteRecording(sessionID: sessionID)
        try await store.deleteSession(id: sessionID)
        try await store.deleteRecoveryJournal(id: sessionID)
    }

    func reconcile() async throws -> [RecoveryItem] {
        let journals = try await store.fetchRecoveryJournals()
        let audio = try await store.fetchRetainedAudio()
        let sessions = try await store.fetchSourceSessions()
        let results = try await store.fetchResultVersions()
        let audioByID = Dictionary(uniqueKeysWithValues: audio.map { ($0.id, $0) })
        let sessionIDs = Set(sessions.map(\.id))
        let resultsBySession = Dictionary(grouping: results, by: \.sessionID)
        var journalByID = Dictionary(uniqueKeysWithValues: journals.map { ($0.id, $0) })

        // The audio metadata is written before capture chunks. If the process dies before
        // the asynchronous journal write, it still produces a deterministic recovery item.
        for record in audio where journalByID[record.id] == nil && sessionIDs.contains(record.id) == false {
            journalByID[record.id] = RecoveryJournalRecord(
                id: record.id,
                updatedAt: record.createdAt,
                phase: record.state == .capturing ? .capturing : .finalizing,
                targetApplication: SessionResultProvenance.legacyUnknown,
                targetBundleIdentifier: nil,
                retainedAudioAvailable: true,
                failureCode: "interrupted"
            )
        }

        var items: [RecoveryItem] = []
        for journal in journalByID.values.sorted(by: { $0.updatedAt > $1.updatedAt }) {
            if journal.phase == .cleaningUp {
                try await retention.deleteRecording(sessionID: journal.id)
                try await store.deleteSession(id: journal.id)
                try await store.deleteRecoveryJournal(id: journal.id)
                continue
            }
            let result = resultsBySession[journal.id]?.max { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            // A successful immutable result proves insertion and persistence completed.
            // A crash before clearing the tiny journal must not create a false recovery.
            if journal.phase == .inserting, result?.insertionSucceeded == true {
                try await store.deleteRecoveryJournal(id: journal.id)
                continue
            }
            let retained = audioByID[journal.id]
            items.append(RecoveryItem(
                journal: journal,
                retainedAudio: retained,
                result: result,
                actions: Self.actions(
                    phase: journal.phase,
                    hasAudio: retained != nil,
                    hasResult: result != nil
                )
            ))
        }
        return items
    }

    static func actions(
        phase: RecoveryPhase,
        hasAudio: Bool,
        hasResult: Bool
    ) -> [RecoveryAction] {
        if phase == .inserting, hasResult { return [.copyText, .delete] }
        if hasAudio { return [.retryTranscription, .retain, .delete] }
        return [.delete]
    }
}
