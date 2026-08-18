import CryptoKit
import Foundation
import Testing
@testable import MurmurNext

@Suite(.serialized)
struct EncryptedAudioVaultTests {
    @Test
    func roundTripUsesChunkEncryptionWithoutPlaintextAudio() async throws {
        let fixture = try AudioVaultFixture()
        let vault = EncryptedAudioVault(rootURL: fixture.rootURL, masterKey: fixture.masterKey)
        let sessionID = UUID()
        let first: [Float] = [0.125, -0.25, 0.5]
        let second: [Float] = [-0.75, 0, 0.875]

        let capturing = try await vault.beginCapture(
            sessionID: sessionID,
            sampleRate: 16_000,
            createdAt: Date(timeIntervalSince1970: 100),
            expiresAt: Date(timeIntervalSince1970: 200)
        )
        try await vault.append(first, sessionID: sessionID)
        try await vault.append(second, sessionID: sessionID)
        let sealed = try await vault.finalize(sessionID: sessionID)

        #expect(capturing.state == .capturing)
        #expect(sealed.state == .sealed)
        #expect(sealed.chunkCount == 2)
        #expect(sealed.sampleCount == 6)
        #expect(try await vault.samples(for: sealed) == first + second)

        let ciphertext = try Data(contentsOf: fixture.rootURL.appendingPathComponent(sealed.relativePath))
        #expect(ciphertext.range(of: Data("RIFF".utf8)) == nil)
        #expect(ciphertext.range(of: Self.floatData(first + second)) == nil)
        #expect(ciphertext.range(of: capturing.wrappedKey) == nil)
    }

    @Test
    func eachRecordingUsesADifferentWrappedDataKey() async throws {
        let fixture = try AudioVaultFixture()
        let vault = EncryptedAudioVault(rootURL: fixture.rootURL, masterKey: fixture.masterKey)

        let first = try await vault.beginCapture(
            sessionID: UUID(), sampleRate: 16_000, createdAt: .now, expiresAt: nil
        )
        let second = try await vault.beginCapture(
            sessionID: UUID(), sampleRate: 16_000, createdAt: .now, expiresAt: nil
        )

        #expect(first.wrappedKey != second.wrappedKey)
    }

    @Test
    func tamperingAndTruncationFailClosed() async throws {
        let fixture = try AudioVaultFixture()
        let vault = EncryptedAudioVault(rootURL: fixture.rootURL, masterKey: fixture.masterKey)
        let sessionID = UUID()
        _ = try await vault.beginCapture(
            sessionID: sessionID, sampleRate: 16_000, createdAt: .now, expiresAt: nil
        )
        try await vault.append([0.1, 0.2, 0.3], sessionID: sessionID)
        let sealed = try await vault.finalize(sessionID: sessionID)
        let url = fixture.rootURL.appendingPathComponent(sealed.relativePath)
        let original = try Data(contentsOf: url)

        var tampered = original
        tampered[tampered.index(before: tampered.endIndex)] ^= 0x01
        try tampered.write(to: url, options: .atomic)
        await #expect(throws: EncryptedAudioVaultError.self) {
            _ = try await vault.samples(for: sealed)
        }

        try Data(original.dropLast()).write(to: url, options: .atomic)
        await #expect(throws: EncryptedAudioVaultError.self) {
            _ = try await vault.samples(for: sealed)
        }
    }

    @Test
    func partialCaptureRecoversOnlyCompleteAuthenticatedChunks() async throws {
        let fixture = try AudioVaultFixture()
        let vault = EncryptedAudioVault(rootURL: fixture.rootURL, masterKey: fixture.masterKey)
        let sessionID = UUID()
        let record = try await vault.beginCapture(
            sessionID: sessionID, sampleRate: 16_000, createdAt: .now, expiresAt: nil
        )
        try await vault.append([0.1, 0.2], sessionID: sessionID)
        try await vault.append([0.3, 0.4], sessionID: sessionID)
        try await vault.simulateInterruptedTailForTesting(sessionID: sessionID)

        #expect(try await vault.recoverPartialSamples(for: record) == [0.1, 0.2, 0.3, 0.4])
    }

    @Test
    func unsafeRecordPathIsRejected() async throws {
        let fixture = try AudioVaultFixture()
        let vault = EncryptedAudioVault(rootURL: fixture.rootURL, masterKey: fixture.masterKey)
        let unsafe = RetainedAudioRecord(
            id: UUID(),
            createdAt: .now,
            expiresAt: nil,
            relativePath: "../private.wav",
            wrappedKey: Data(repeating: 1, count: 60),
            sampleRate: 16_000,
            state: .sealed
        )

        await #expect(throws: EncryptedAudioVaultError.self) {
            _ = try await vault.samples(for: unsafe)
        }
    }

    @Test
    func wrongMasterKeyAndReorderedChunksAreRejected() async throws {
        let fixture = try AudioVaultFixture()
        let vault = EncryptedAudioVault(rootURL: fixture.rootURL, masterKey: fixture.masterKey)
        let sessionID = UUID()
        _ = try await vault.beginCapture(
            sessionID: sessionID, sampleRate: 16_000, createdAt: .now, expiresAt: nil
        )
        try await vault.append([0.1, 0.2], sessionID: sessionID)
        try await vault.append([0.3, 0.4], sessionID: sessionID)
        let record = try await vault.finalize(sessionID: sessionID)

        let wrongKeyVault = EncryptedAudioVault(
            rootURL: fixture.rootURL,
            masterKey: SymmetricKey(data: Data(repeating: 0x99, count: 32))
        )
        await #expect(throws: EncryptedAudioVaultError.self) {
            _ = try await wrongKeyVault.samples(for: record)
        }

        let url = fixture.rootURL.appendingPathComponent(record.relativePath)
        let original = try Data(contentsOf: url)
        try Self.reorderingFirstTwoChunks(in: original).write(to: url, options: .atomic)
        await #expect(throws: EncryptedAudioVaultError.self) {
            _ = try await vault.samples(for: record)
        }
    }

    private static func floatData(_ values: [Float]) -> Data {
        values.withUnsafeBytes { Data($0) }
    }

    private static func reorderingFirstTwoChunks(in data: Data) throws -> Data {
        func uint32(at offset: Int) -> Int {
            Int(data[offset]) << 24
                | Int(data[offset + 1]) << 16
                | Int(data[offset + 2]) << 8
                | Int(data[offset + 3])
        }
        let headerEnd = 8 + uint32(at: 4)
        let firstEnd = headerEnd + 4 + uint32(at: headerEnd)
        let secondEnd = firstEnd + 4 + uint32(at: firstEnd)
        guard secondEnd <= data.count else { throw EncryptedAudioVaultError.truncated }
        var reordered = data.prefix(headerEnd)
        reordered.append(data[firstEnd..<secondEnd])
        reordered.append(data[headerEnd..<firstEnd])
        reordered.append(data[secondEnd...])
        return Data(reordered)
    }
}

private struct AudioVaultFixture {
    let rootURL: URL
    let masterKey = SymmetricKey(data: Data(repeating: 0x51, count: 32))

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmur-audio-vault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }
}
