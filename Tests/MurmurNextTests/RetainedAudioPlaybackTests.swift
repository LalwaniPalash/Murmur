import CryptoKit
import Foundation
import Testing
@testable import MurmurNext

@MainActor
@Suite(.serialized)
struct RetainedAudioPlaybackTests {
    @Test
    func decryptsDirectlyIntoAudioOutputWithoutTemporaryFiles() async throws {
        let fixture = try PlaybackFixture()
        let sessionID = UUID()
        _ = try await fixture.retention.begin(
            sessionID: sessionID,
            policy: .sevenDays,
            sampleRate: 16_000,
            createdAt: .now
        )
        try await fixture.retention.append([0.1, -0.2, 0.3], sessionID: sessionID)
        _ = try await fixture.retention.finalize(sessionID: sessionID)
        let output = AudioOutputSpy()
        let playback = RetainedAudioPlayback(retention: fixture.retention, output: output)

        try await playback.play(sessionID: sessionID)

        #expect(output.samples == [0.1, -0.2, 0.3])
        #expect(output.sampleRate == 16_000)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.directoryURL.path)
            .filter { $0.hasSuffix(".wav") }.isEmpty)
    }

    @Test
    func authenticationFailureSchedulesNoAudio() async throws {
        let fixture = try PlaybackFixture()
        let sessionID = UUID()
        _ = try await fixture.retention.begin(
            sessionID: sessionID,
            policy: .sevenDays,
            sampleRate: 16_000,
            createdAt: .now
        )
        try await fixture.retention.append([0.1], sessionID: sessionID)
        let record = try await fixture.retention.finalize(sessionID: sessionID)
        let url = fixture.audioURL.appendingPathComponent(record.relativePath)
        var data = try Data(contentsOf: url)
        data[data.index(before: data.endIndex)] ^= 1
        try data.write(to: url, options: .atomic)
        let output = AudioOutputSpy()

        await #expect(throws: EncryptedAudioVaultError.self) {
            try await RetainedAudioPlayback(retention: fixture.retention, output: output)
                .play(sessionID: sessionID)
        }
        #expect(output.samples.isEmpty)
    }
}

@MainActor
private final class AudioOutputSpy: RetainedAudioOutputServicing {
    var samples: [Float] = []
    var sampleRate = 0
    func play(samples: [Float], sampleRate: Int) {
        self.samples = samples
        self.sampleRate = sampleRate
    }
    func stop() {}
}

private struct PlaybackFixture {
    let directoryURL: URL
    let audioURL: URL
    let retention: RetentionCoordinator

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmur-playback-\(UUID().uuidString)", isDirectory: true)
        audioURL = directoryURL.appendingPathComponent("Audio", isDirectory: true)
        try FileManager.default.createDirectory(at: audioURL, withIntermediateDirectories: true)
        let key = SymmetricKey(data: Data(repeating: 0x84, count: 32))
        let store = try SecureRecordStore(url: directoryURL.appendingPathComponent("store.sqlite"), key: key)
        retention = RetentionCoordinator(
            vault: EncryptedAudioVault(rootURL: audioURL, masterKey: key),
            store: store
        )
    }
}
