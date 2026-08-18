import CryptoKit
import Foundation
import Testing
@testable import MurmurNext

@Suite(.serialized)
struct IssueBundleServiceTests {
    @Test
    func defaultBundleIsContentFreeAndPreviewListsExcludedPrivateFields() async throws {
        let fixture = try IssueBundleFixture()
        let request = fixture.request(
            raw: "RAW-PRIVATE-CANARY",
            final: "FINAL-PRIVATE-CANARY"
        )
        let service = fixture.service()

        let preview = try await service.preview(request: request, options: .init())
        let data = try await service.makeBundle(
            request: request,
            options: .init(),
            exportedAt: Date(timeIntervalSince1970: 500)
        )
        let document = try fixture.decode(data)

        #expect(preview.includesPrivateContent == false)
        #expect(preview.fields.first(where: { $0.path == "transcript.raw" })?.isIncluded == false)
        #expect(preview.fields.first(where: { $0.path == "audio.waveData" })?.isIncluded == false)
        #expect(document.transcript == nil)
        #expect(document.audio == nil)
        #expect(document.consent.transcriptIncluded == false)
        #expect(document.consent.audioIncluded == false)
        #expect(data.range(of: Data("RAW-PRIVATE-CANARY".utf8)) == nil)
        #expect(data.range(of: Data("FINAL-PRIVATE-CANARY".utf8)) == nil)
        #expect(data.range(of: Data("RIFF".utf8)) == nil)
    }

    @Test
    func transcriptAndAudioRequireIndependentExplicitConsent() async throws {
        let fixture = try IssueBundleFixture()
        let request = fixture.request(raw: "Exact raw.", final: "Exact final.")
        try await fixture.retain(sessionID: request.session.id)
        let service = fixture.service()

        let transcriptOnly = try await service.makeBundle(
            request: request,
            options: IssueBundleOptions(includeTranscript: true, includeAudio: false)
        )
        let transcriptDocument = try fixture.decode(transcriptOnly)
        #expect(transcriptDocument.transcript == .init(raw: "Exact raw.", final: "Exact final."))
        #expect(transcriptDocument.audio == nil)

        let audioOnly = try await service.makeBundle(
            request: request,
            options: IssueBundleOptions(includeTranscript: false, includeAudio: true)
        )
        let audioDocument = try fixture.decode(audioOnly)
        #expect(audioDocument.transcript == nil)
        #expect(audioDocument.audio?.format == "wav-pcm16-mono")
        #expect(audioDocument.audio?.sampleRate == 16_000)
        #expect(audioDocument.audio?.sampleCount == 3)
        #expect(audioDocument.audio?.waveData.prefix(4) == Data("RIFF".utf8))
    }

    @Test
    func bundleSchemaCannotContainSecretsPathsOrUnrelatedSessions() async throws {
        let fixture = try IssueBundleFixture()
        let request = fixture.request(raw: "Selected transcript.", final: "Selected transcript.")
        let unrelated = UUID().uuidString
        let data = try await fixture.service().makeBundle(
            request: request,
            options: IssueBundleOptions(includeTranscript: true, includeAudio: false)
        )
        let string = try #require(String(data: data, encoding: .utf8))

        #expect(string.contains("Selected transcript."))
        #expect(string.contains(request.session.id.uuidString))
        #expect(string.contains(unrelated) == false)
        #expect(string.contains("wrappedKey") == false)
        #expect(string.contains("fileURL") == false)
        #expect(string.contains("apiKey") == false)
        #expect(string.contains("clipboard") == false)
    }
}

private struct IssueBundleFixture {
    let directory: URL
    let retention: RetentionCoordinator

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmur-issue-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let audioDirectory = directory.appendingPathComponent("Audio", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        let key = SymmetricKey(data: Data(repeating: 0x36, count: 32))
        let store = try SecureRecordStore(
            url: directory.appendingPathComponent("store.sqlite"),
            key: key
        )
        retention = RetentionCoordinator(
            vault: EncryptedAudioVault(rootURL: audioDirectory, masterKey: key),
            store: store
        )
    }

    func service() -> IssueBundleService {
        IssueBundleService(
            retention: retention,
            appVersion: "2.0-test",
            operatingSystem: "TestOS",
            architecture: "arm64"
        )
    }

    func request(raw: String, final: String) -> IssueBundleRequest {
        let sessionID = UUID()
        let session = SourceSessionRecord(
            id: sessionID,
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 104),
            sourceApplication: "Private App Name",
            sourceBundleIdentifier: "private.bundle.identifier",
            context: .general,
            mode: .pushToTalk,
            recordingDuration: 4
        )
        return IssueBundleRequest(
            session: session,
            result: TranscriptResultVersion(
                id: UUID(),
                sessionID: sessionID,
                createdAt: Date(timeIntervalSince1970: 105),
                rawTranscript: raw,
                finalTranscript: final,
                providerIdentifier: "local-whisper",
                modelIdentifier: "small.en",
                language: "en",
                totalProcessingDuration: 0.4,
                insertionSucceeded: false
            ),
            failureCode: "insertion-failed",
            modelSHA256: String(repeating: "a", count: 64)
        )
    }

    func retain(sessionID: UUID) async throws {
        _ = try await retention.begin(
            sessionID: sessionID,
            policy: .sevenDays,
            sampleRate: 16_000,
            createdAt: .now
        )
        try await retention.append([0.25, -0.5, 0.75], sessionID: sessionID)
        _ = try await retention.finalize(sessionID: sessionID)
    }

    func decode(_ data: Data) throws -> IssueBundleDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(IssueBundleDocument.self, from: data)
    }
}
