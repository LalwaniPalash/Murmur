import Foundation
import Testing

@testable import MurmurQualityCore

struct CorpusRunnerTests {
    @Test func unavailableModelProducesExplicitSkipsWithoutResolvingAudio() async {
        let manifest = AudioCorpusManifest(version: 1, fixtures: [Self.fixture(id: "one")])
        let report = await CorpusRunner.run(
            manifest: manifest,
            baseDirectory: URL(fileURLWithPath: "/definitely/missing"),
            modelIdentifier: "unavailable",
            modelAvailable: false
        ) { _, _ in
            Issue.record("The transcription closure must not run without a model.")
            return ""
        }

        #expect(report.completedFixtureCount == 0)
        #expect(report.failedFixtureCount == 0)
        #expect(report.skippedFixtureCount == 1)
        #expect(report.results[0].reason == "model unavailable")
    }

    @Test func missingRequiredMiddlePhraseFailsEvenWhenTranscriptIsFluent() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmur-runner-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data([0]).write(to: directory.appendingPathComponent("fixture.wav"))

        let report = await CorpusRunner.run(
            manifest: AudioCorpusManifest(version: 1, fixtures: [Self.fixture(id: "middle")]),
            baseDirectory: directory,
            modelIdentifier: "test-model",
            modelAvailable: true
        ) { _, _ in
            "Opening words are present. Closing words are present."
        }

        #expect(report.completedFixtureCount == 1)
        #expect(report.failedFixtureCount == 1)
        #expect(report.results[0].status == .failed)
        #expect(report.results[0].completeness?.isComplete == false)
    }

    private static func fixture(id: String) -> AudioCorpusFixture {
        AudioCorpusFixture(
            id: id,
            source: .audioFile(path: "fixture.wav"),
            expectedTranscript: "Opening words are present. Essential middle words remain. Closing words are present.",
            requiredPhrases: [
                RequiredPhrase(text: "Opening words", region: .beginning),
                RequiredPhrase(text: "Essential middle words", region: .middle),
                RequiredPhrase(text: "Closing words", region: .end),
            ],
            protectedTokens: ["Essential"],
            language: "en",
            speechCondition: .normal,
            microphoneClass: .synthetic,
            tags: ["completeness"],
            consent: CorpusConsent(origin: .synthetic, license: "CC0-1.0")
        )
    }
}
