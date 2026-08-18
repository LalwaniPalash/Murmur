import Foundation
import Testing

@testable import MurmurQualityCore

struct CorpusManifestTests {
    @Test func decodesAndValidatesVersionedSyntheticFixture() throws {
        let data = Data(Self.validManifest.utf8)
        let manifest = try CorpusManifestLoader.decode(data)
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let validated = try CorpusManifestValidator.validate(manifest, baseDirectory: directory)

        #expect(validated.version == 1)
        #expect(validated.fixtures.count == 1)
        #expect(validated.fixtures[0].id == "quiet-opening-middle-ending")
        #expect(validated.fixtures[0].source.synthesisText == "Opening phrase. Middle phrase. Ending phrase.")
    }

    @Test func rejectsDuplicateIDsAndUnlicensedFixtures() throws {
        let fixture = try CorpusManifestLoader.decode(Data(Self.validManifest.utf8)).fixtures[0]
        let duplicate = AudioCorpusManifest(version: 1, fixtures: [
            fixture,
            AudioCorpusFixture(
                id: fixture.id,
                source: fixture.source,
                expectedTranscript: fixture.expectedTranscript,
                requiredPhrases: fixture.requiredPhrases,
                protectedTokens: [],
                language: "en",
                speechCondition: .normal,
                microphoneClass: .synthetic,
                tags: [],
                consent: CorpusConsent(origin: .synthetic, license: "")
            ),
        ])
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let error = #expect(throws: CorpusManifestValidationError.self) {
            try CorpusManifestValidator.validate(duplicate, baseDirectory: directory)
        }

        #expect(error?.issues.contains(where: { $0.code == .duplicateFixtureID }) == true)
        #expect(error?.issues.contains(where: { $0.code == .missingLicense }) == true)
    }

    @Test func rejectsTraversalMissingFilesAndUnsupportedFormats() throws {
        let manifest = AudioCorpusManifest(version: 1, fixtures: [
            Self.recordedFixture(id: "traversal", path: "../private.wav"),
            Self.recordedFixture(id: "missing", path: "missing.wav"),
            Self.recordedFixture(id: "unsupported", path: "fixture.exe"),
        ])
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let error = #expect(throws: CorpusManifestValidationError.self) {
            try CorpusManifestValidator.validate(manifest, baseDirectory: directory)
        }

        #expect(error?.issues.contains(where: { $0.fixtureID == "traversal" && $0.code == .unsafePath }) == true)
        #expect(error?.issues.contains(where: { $0.fixtureID == "missing" && $0.code == .missingAudioFile }) == true)
        #expect(error?.issues.contains(where: { $0.fixtureID == "unsupported" && $0.code == .unsupportedAudioFormat }) == true)
    }

    @Test func recordedFixturesRequirePermissionAndMatchingDigest() throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let audioURL = directory.appendingPathComponent("sample.wav")
        try Data("audio".utf8).write(to: audioURL)

        let missingPermission = AudioCorpusManifest(version: 1, fixtures: [
            Self.recordedFixture(id: "recorded", path: "sample.wav", permissionReference: nil),
        ])
        let permissionError = #expect(throws: CorpusManifestValidationError.self) {
            try CorpusManifestValidator.validate(missingPermission, baseDirectory: directory)
        }
        #expect(permissionError?.issues.contains(where: { $0.code == .missingPermissionReference }) == true)

        var digestMismatch = Self.recordedFixture(
            id: "recorded",
            path: "sample.wav",
            permissionReference: "consent-001"
        )
        digestMismatch.expectedSHA256 = String(repeating: "0", count: 64)
        let digestError = #expect(throws: CorpusManifestValidationError.self) {
            try CorpusManifestValidator.validate(
                AudioCorpusManifest(version: 1, fixtures: [digestMismatch]),
                baseDirectory: directory
            )
        }
        #expect(digestError?.issues.contains(where: { $0.code == .digestMismatch }) == true)
    }

    @Test func computesReproducibleFixtureDigest() throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let audioURL = directory.appendingPathComponent("sample.wav")
        try Data("audio".utf8).write(to: audioURL)

        let first = try CorpusFixtureDigest.sha256(of: audioURL)
        let second = try CorpusFixtureDigest.sha256(of: audioURL)

        #expect(first == second)
        #expect(first.count == 64)
    }

    private static func recordedFixture(
        id: String,
        path: String,
        permissionReference: String? = "consent-001"
    ) -> AudioCorpusFixture {
        AudioCorpusFixture(
            id: id,
            source: .audioFile(path: path),
            expectedTranscript: "Expected words.",
            requiredPhrases: [],
            protectedTokens: [],
            language: "en",
            speechCondition: .normal,
            microphoneClass: .builtIn,
            tags: [],
            consent: CorpusConsent(
                origin: .recorded,
                license: "CC-BY-4.0",
                permissionReference: permissionReference
            )
        )
    }

    private static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmur-quality-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static let validManifest = #"""
    {
      "version": 1,
      "fixtures": [
        {
          "id": "quiet-opening-middle-ending",
          "source": {
            "kind": "synthesis",
            "text": "Opening phrase. Middle phrase. Ending phrase.",
            "voice": "Samantha",
            "rate": 180
          },
          "expectedTranscript": "Opening phrase. Middle phrase. Ending phrase.",
          "requiredPhrases": [
            { "text": "Opening phrase", "region": "beginning" },
            { "text": "Middle phrase", "region": "middle" },
            { "text": "Ending phrase", "region": "end" }
          ],
          "protectedTokens": ["Opening", "Middle", "Ending"],
          "language": "en",
          "speechCondition": "quiet",
          "microphoneClass": "synthetic",
          "tags": ["completeness", "quiet"],
          "consent": {
            "origin": "synthetic",
            "license": "CC0-1.0"
          }
        }
      ]
    }
    """#
}
