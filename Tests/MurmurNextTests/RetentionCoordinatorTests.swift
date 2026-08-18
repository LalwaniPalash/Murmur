import CryptoKit
import Foundation
import Testing
@testable import MurmurNext

@Suite(.serialized)
struct RetentionCoordinatorTests {
    @Test
    func disabledRetentionCreatesNoMetadataOrCiphertext() async throws {
        let fixture = try RetentionFixture()

        let record = try await fixture.coordinator.begin(
            sessionID: UUID(),
            policy: .disabled,
            sampleRate: 16_000,
            createdAt: .now
        )

        #expect(record == nil)
        #expect(try await fixture.store.fetchRetainedAudio().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.audioURL.path).isEmpty)
    }

    @Test(arguments: [
        AudioRetentionPolicy.oneDay,
        .sevenDays,
        .thirtyDays,
        .untilDeleted,
    ])
    func enabledPoliciesPersistOnlyEncryptedAudio(policy: AudioRetentionPolicy) async throws {
        let fixture = try RetentionFixture()
        let sessionID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_000)
        _ = try await fixture.coordinator.begin(
            sessionID: sessionID,
            policy: policy,
            sampleRate: 16_000,
            createdAt: createdAt
        )
        try await fixture.coordinator.append([0.2, -0.3], sessionID: sessionID)
        let sealed = try await fixture.coordinator.finalize(sessionID: sessionID)

        #expect(sealed.expiresAt == policy.expirationDate(createdAt: createdAt))
        #expect(try await fixture.store.fetchRetainedAudio() == [sealed])
        let ciphertext = try Data(contentsOf: fixture.audioURL.appendingPathComponent(sealed.relativePath))
        #expect(ciphertext.range(of: Data("RIFF".utf8)) == nil)
    }

    @Test
    func expirationCryptoShredsMetadataBeforeRemovingCiphertext() async throws {
        let events = RetentionEventLog()
        let record = RetainedAudioRecord(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 100),
            expiresAt: Date(timeIntervalSince1970: 200),
            relativePath: "placeholder.mra",
            wrappedKey: Data(repeating: 7, count: 60),
            sampleRate: 16_000,
            state: .sealed
        )
        let store = RetentionStoreSpy(records: [record], events: events)
        let vault = RetentionVaultSpy(events: events)
        let coordinator = RetentionCoordinator(vault: vault, store: store)

        #expect(try await coordinator.purgeExpired(at: Date(timeIntervalSince1970: 199)) == 0)
        #expect(try await coordinator.purgeExpired(at: Date(timeIntervalSince1970: 200)) == 1)
        #expect(await events.values == ["metadata", "ciphertext"])
    }

    @Test
    func legacyPlaintextWaveIsEncryptedBeforeItIsRemoved() async throws {
        let fixture = try RetentionFixture()
        let sessionID = UUID()
        let legacyURL = fixture.audioURL.appendingPathComponent("\(sessionID.uuidString).wav")
        let original: [Float] = [0.1, -0.2, 0.3]
        try WaveFileEncoder.encode(samples: original).write(to: legacyURL, options: .atomic)

        #expect(try await fixture.coordinator.migrateLegacyRecordings(policy: .sevenDays) == 1)

        let record = try #require(try await fixture.store.fetchRetainedAudio().first)
        #expect(FileManager.default.fileExists(atPath: legacyURL.path) == false)
        let recovered = try await fixture.vault.samples(for: record)
        #expect(recovered.count == original.count)
        for (actual, expected) in zip(recovered, original) {
            #expect(abs(actual - expected) < 0.0001)
        }
    }
}

private struct RetentionFixture {
    let directoryURL: URL
    let audioURL: URL
    let store: SecureRecordStore
    let vault: EncryptedAudioVault
    let coordinator: RetentionCoordinator

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmur-retention-\(UUID().uuidString)", isDirectory: true)
        audioURL = directoryURL.appendingPathComponent("Audio", isDirectory: true)
        try FileManager.default.createDirectory(at: audioURL, withIntermediateDirectories: true)
        let key = SymmetricKey(data: Data(repeating: 0x62, count: 32))
        store = try SecureRecordStore(url: directoryURL.appendingPathComponent("store.sqlite"), key: key)
        vault = EncryptedAudioVault(rootURL: audioURL, masterKey: key)
        coordinator = RetentionCoordinator(vault: vault, store: store)
    }
}

private actor RetentionEventLog {
    private(set) var values: [String] = []
    func append(_ value: String) { values.append(value) }
}

private actor RetentionStoreSpy: RetainedAudioMetadataStoring {
    private var records: [RetainedAudioRecord]
    private let events: RetentionEventLog

    init(records: [RetainedAudioRecord], events: RetentionEventLog) {
        self.records = records
        self.events = events
    }

    func saveRetainedAudio(_ record: RetainedAudioRecord) async throws {
        records.removeAll { $0.id == record.id }
        records.append(record)
    }

    func fetchRetainedAudio() async throws -> [RetainedAudioRecord] { records }

    func deleteRetainedAudio(id: UUID) async throws {
        await events.append("metadata")
        records.removeAll { $0.id == id }
    }
}

private actor RetentionVaultSpy: RetainedAudioVaultServicing {
    private let events: RetentionEventLog

    init(events: RetentionEventLog) { self.events = events }

    func beginCapture(
        sessionID: UUID,
        sampleRate: Int,
        createdAt: Date,
        expiresAt: Date?
    ) async throws -> RetainedAudioRecord {
        throw EncryptedAudioVaultError.captureNotFound
    }

    func append(_ samples: [Float], sessionID: UUID) async throws {}
    func finalize(sessionID: UUID) async throws -> RetainedAudioRecord {
        throw EncryptedAudioVaultError.captureNotFound
    }
    func cancel(sessionID: UUID, deleteCiphertext: Bool) async throws {}
    func deleteCiphertext(for record: RetainedAudioRecord) async throws {
        await events.append("ciphertext")
    }
    func legacyRecordings() async throws -> [EncryptedAudioVault.LegacyRecording] { [] }
    func deleteLegacyRecording(sessionID: UUID) async throws {}
    func removeOrphanedCiphertext(keeping relativePaths: Set<String>) async throws {}
    func samples(for record: RetainedAudioRecord) async throws -> [Float] { [] }
    func recoverPartialSamples(for record: RetainedAudioRecord) async throws -> [Float] { [] }
}
