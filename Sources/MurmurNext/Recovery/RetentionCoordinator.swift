import Foundation

protocol RetainedAudioVaultServicing: Sendable {
    func beginCapture(
        sessionID: UUID,
        sampleRate: Int,
        createdAt: Date,
        expiresAt: Date?
    ) async throws -> RetainedAudioRecord
    func append(_ samples: [Float], sessionID: UUID) async throws
    func finalize(sessionID: UUID) async throws -> RetainedAudioRecord
    func cancel(sessionID: UUID, deleteCiphertext: Bool) async throws
    func deleteCiphertext(for record: RetainedAudioRecord) async throws
    func legacyRecordings() async throws -> [EncryptedAudioVault.LegacyRecording]
    func deleteLegacyRecording(sessionID: UUID) async throws
    func removeOrphanedCiphertext(keeping relativePaths: Set<String>) async throws
    func samples(for record: RetainedAudioRecord) async throws -> [Float]
    func recoverPartialSamples(for record: RetainedAudioRecord) async throws -> [Float]
}

extension EncryptedAudioVault: RetainedAudioVaultServicing {}

protocol RetainedAudioMetadataStoring: Sendable {
    func saveRetainedAudio(_ record: RetainedAudioRecord) async throws
    func fetchRetainedAudio() async throws -> [RetainedAudioRecord]
    func deleteRetainedAudio(id: UUID) async throws
}

extension SecureRecordStore: RetainedAudioMetadataStoring {}

actor RetentionCoordinator {
    private let vault: any RetainedAudioVaultServicing
    private let store: any RetainedAudioMetadataStoring

    init(
        vault: any RetainedAudioVaultServicing,
        store: any RetainedAudioMetadataStoring
    ) {
        self.vault = vault
        self.store = store
    }

    func begin(
        sessionID: UUID,
        policy: AudioRetentionPolicy,
        sampleRate: Int,
        createdAt: Date
    ) async throws -> RetainedAudioRecord? {
        guard policy.isEnabled else { return nil }
        let record = try await vault.beginCapture(
            sessionID: sessionID,
            sampleRate: sampleRate,
            createdAt: createdAt,
            expiresAt: policy.expirationDate(createdAt: createdAt)
        )
        do {
            try await store.saveRetainedAudio(record)
            return record
        } catch {
            try? await vault.cancel(sessionID: sessionID, deleteCiphertext: true)
            throw error
        }
    }

    func append(_ samples: [Float], sessionID: UUID) async throws {
        try await vault.append(samples, sessionID: sessionID)
    }

    func finalize(sessionID: UUID) async throws -> RetainedAudioRecord {
        let record = try await vault.finalize(sessionID: sessionID)
        try await store.saveRetainedAudio(record)
        return record
    }

    func cancel(sessionID: UUID, deleteCiphertext: Bool) async throws {
        guard deleteCiphertext else {
            try await vault.cancel(sessionID: sessionID, deleteCiphertext: false)
            return
        }
        let record = try await store.fetchRetainedAudio().first { $0.id == sessionID }
        try await vault.cancel(sessionID: sessionID, deleteCiphertext: false)
        try await store.deleteRetainedAudio(id: sessionID)
        if let record { try await vault.deleteCiphertext(for: record) }
    }

    @discardableResult
    func purgeExpired(at date: Date) async throws -> Int {
        let expired = try await store.fetchRetainedAudio().filter {
            guard let expiresAt = $0.expiresAt else { return false }
            return expiresAt <= date
        }
        for record in expired {
            try await cryptoShred(record)
        }
        return expired.count
    }

    @discardableResult
    func purgeAll() async throws -> Int {
        let records = try await store.fetchRetainedAudio()
        for record in records {
            try await cryptoShred(record)
        }
        return records.count
    }

    func deleteRecording(sessionID: UUID) async throws {
        guard let record = try await store.fetchRetainedAudio().first(where: { $0.id == sessionID })
        else { return }
        try await cryptoShred(record)
    }

    func apply(policy: AudioRetentionPolicy, at date: Date) async throws {
        guard policy.isEnabled else {
            _ = try await purgeAll()
            return
        }
        for record in try await store.fetchRetainedAudio() where record.state == .sealed {
            let updated = RetainedAudioRecord(
                schemaVersion: record.schemaVersion,
                id: record.id,
                createdAt: record.createdAt,
                expiresAt: policy.expirationDate(createdAt: record.createdAt),
                relativePath: record.relativePath,
                wrappedKey: record.wrappedKey,
                sampleRate: record.sampleRate,
                sampleCount: record.sampleCount,
                chunkCount: record.chunkCount,
                byteCount: record.byteCount,
                state: record.state
            )
            try await store.saveRetainedAudio(updated)
        }
        _ = try await purgeExpired(at: date)
    }

    @discardableResult
    func migrateLegacyRecordings(policy: AudioRetentionPolicy) async throws -> Int {
        var migrated = 0
        let effectivePolicy = policy.isEnabled ? policy : .untilDeleted
        let existingIDs = Set(try await store.fetchRetainedAudio().map(\.id))
        for legacy in try await vault.legacyRecordings() where existingIDs.contains(legacy.sessionID) == false {
            guard try await begin(
                sessionID: legacy.sessionID,
                policy: effectivePolicy,
                sampleRate: legacy.sampleRate,
                createdAt: legacy.createdAt
            ) != nil else { continue }
            for start in stride(from: 0, to: legacy.samples.count, by: 16_000) {
                let end = min(start + 16_000, legacy.samples.count)
                try await append(Array(legacy.samples[start..<end]), sessionID: legacy.sessionID)
            }
            _ = try await finalize(sessionID: legacy.sessionID)
            try await vault.deleteLegacyRecording(sessionID: legacy.sessionID)
            migrated += 1
        }
        return migrated
    }

    func reconcileOrphanedCiphertext() async throws {
        let knownPaths = Set(try await store.fetchRetainedAudio().map(\.relativePath))
        try await vault.removeOrphanedCiphertext(keeping: knownPaths)
    }

    func retainedRecord(sessionID: UUID) async throws -> RetainedAudioRecord? {
        try await store.fetchRetainedAudio().first { $0.id == sessionID }
    }

    func samples(sessionID: UUID) async throws -> (samples: [Float], sampleRate: Int) {
        guard let record = try await retainedRecord(sessionID: sessionID) else {
            throw EncryptedAudioVaultError.captureNotFound
        }
        let samples = record.state == .sealed
            ? try await vault.samples(for: record)
            : try await vault.recoverPartialSamples(for: record)
        return (samples, record.sampleRate)
    }

    private func cryptoShred(_ record: RetainedAudioRecord) async throws {
        // Removing the encrypted metadata destroys the only persisted copy of the wrapped
        // data key. Ciphertext deletion follows and is safe to retry through orphan cleanup.
        try await store.deleteRetainedAudio(id: record.id)
        try await vault.deleteCiphertext(for: record)
    }
}
